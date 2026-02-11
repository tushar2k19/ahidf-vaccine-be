class Api::PublicChatController < ApplicationController
  # No authentication required for public chatbot
  # skip_before_action :authenticate_user!, only: [:create_thread, :send_message, :web_search]
  
  # Create a new chat thread for public user
  def create_thread
    service = OpenaiService.new
    thread_id = service.create_thread
    
    render json: { thread_id: thread_id }, status: :ok
  rescue => e
    Rails.logger.error "Error creating public thread: #{e.message}"
    render json: { error: 'Failed to create chat thread' }, status: :internal_server_error
  end
  
  # Send message to public assistant
  def send_message
    thread_id = params[:thread_id]
    message = params[:message]
    
    unless thread_id && message
      return render json: { error: 'Missing thread_id or message' }, status: :bad_request
    end
    
    service = OpenaiService.new
    
    # Send message to thread
    service.send_message(thread_id, message)
    
    # Create run with public assistant
    instructions = "Search the AHIDF knowledge base documents thoroughly. If you cannot find the answer in the documents, clearly state that and ask if the user wants to search the internet."
    
    # Use the PUBLIC assistant ID from env (not AHIDF_ASSISTANT_ID which is for DPR analyzer)
    assistant_id = ENV['PUBLIC_ASSISTANT_ID']
    
    Rails.logger.info "=== Public Chat Assistant ID Check ==="
    Rails.logger.info "PUBLIC_ASSISTANT_ID from ENV: #{ENV['PUBLIC_ASSISTANT_ID']}"
    Rails.logger.info "AHIDF_ASSISTANT_ID from ENV: #{ENV['AHIDF_ASSISTANT_ID']}"
    Rails.logger.info "Using assistant_id: #{assistant_id}"
    Rails.logger.info "================================"
    
    unless assistant_id.present?
      Rails.logger.error "PUBLIC_ASSISTANT_ID not configured in environment variables"
      return render json: { error: 'Public assistant not configured' }, status: :internal_server_error
    end
    
    Rails.logger.info "Creating run with assistant_id: #{assistant_id} for thread: #{thread_id}"
    
    run_id = service.create_run_with_custom_assistant(
      thread_id, 
      assistant_id,
      instructions: instructions
    )
    
    Rails.logger.info "Created run_id: #{run_id} with assistant: #{assistant_id}"
    
    # Wait for completion (using existing wait method)
    # The wait_for_run_completion method in OpenaiService handles polling
    run_data = service.wait_for_run_completion(thread_id, run_id)
    
    if run_data['status'] != 'completed'
      return render json: { error: "Assistant run failed with status: #{run_data['status']}" }, status: :internal_server_error
    end
    
    # Get messages
    messages_response = service.get_thread_messages(thread_id, limit: 1)
    
    # Extract the last message content
    last_message = messages_response['data'].first
    
    if last_message
      # Parse the content to find text and potential citations
      response_data = parse_openai_message(last_message)
      
      # Check if response indicates no answer found
      # We check both the parsed JSON (if assistant returned JSON) and the raw text
      text_content = response_data[:text]
      json_content = response_data[:json_content]
      
      needs_web_search = false
      if json_content && json_content['needs_consent']
        needs_web_search = true
      else
        needs_web_search = check_if_needs_web_search(text_content)
      end
      
      # Clean citation markers from JSON answer if present
      if json_content && json_content['answer']
        json_content['answer'] = strip_citation_markers(json_content['answer'])
      end
      
      render json: {
        response: json_content || text_content, # Return parsed JSON object or text
        citations: response_data[:citations],
        needs_consent: needs_web_search,
        source: 'documents',
        is_json: json_content.present?
      }, status: :ok
    else
      render json: { error: 'No response from assistant' }, status: :internal_server_error
    end
    
  rescue => e
    Rails.logger.error "Error in public chat: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render json: { error: 'Failed to process message' }, status: :internal_server_error
  end
  
  # Web search fallback
  def web_search
    query = params[:query]
    
    unless query
      return render json: { error: 'Missing query' }, status: :bad_request
    end
    
    perplexity = PerplexityService.new
    result = perplexity.search(query)
    
    render json: result, status: :ok
    
  rescue => e
    Rails.logger.error "Error in web search: #{e.message}"
    render json: { error: 'Failed to search the web' }, status: :internal_server_error
  end
  
  private
  
  def parse_openai_message(message)
    content_blocks = message['content']
    text = ""
    citations = []
    json_content = nil
    seen_citations = [] # Track normalized citation names to avoid duplicates
    
    content_blocks.each do |block|
      if block['type'] == 'text'
        block_text = block['text']['value']
        
        # Extract citation markers from text (format: 【number:number†filename.pdf】)
        citation_markers = block_text.scan(/【[^】]+】/)
        
        # Extract document names from citation markers and add to citations
        citation_markers.each do |marker|
          # Extract filename from marker (format: 【10:3†SR_THORAT_MILK_DPR.pdf】)
          if marker =~ /†([^】]+)/
            doc_name = $1
            cleaned_name = clean_document_name(doc_name)
            normalized_name = cleaned_name.downcase.strip
            # Avoid duplicates using normalized name
            unless seen_citations.include?(normalized_name)
              seen_citations << normalized_name
              citations << { title: cleaned_name, url: '#' }
            end
          end
        end
        
        # Strip citation markers from text
        cleaned_text = strip_citation_markers(block_text)
        text += cleaned_text
        
        # Try to parse as JSON if it looks like JSON
        if cleaned_text.strip.start_with?('{') && cleaned_text.strip.end_with?('}')
          begin
            parsed = JSON.parse(cleaned_text)
            # Validate it has the expected fields
            if parsed.is_a?(Hash) && (parsed.key?('answer') || parsed.key?('response'))
              json_content = parsed
            end
          rescue JSON::ParserError
            # Not valid JSON, treat as text
          end
        end
        
        # Extract citations from annotations (OpenAI's structured citations)
        if block['text']['annotations']
          block['text']['annotations'].each do |annotation|
            if annotation['type'] == 'file_citation'
              file_id = annotation['file_citation']['file_id']
              # Try to get document name from annotation text (which might contain citation marker)
              # or extract from file_id mapping if available
              annotation_text = annotation['text'] || ''
              
              # If annotation text contains citation marker, extract from it
              if annotation_text =~ /†([^】]+)/
                doc_name = $1
              elsif annotation_text.present?
                doc_name = annotation_text
              else
                # Fallback to file_id (we'll try to map it or use a generic name)
                doc_name = file_id
              end
              
              cleaned_name = clean_document_name(doc_name)
              normalized_name = cleaned_name.downcase.strip
              
              # Avoid duplicates using normalized name
              unless seen_citations.include?(normalized_name)
                seen_citations << normalized_name
                citations << { title: cleaned_name, file_id: file_id, url: '#' }
              end
            end
          end
        end
      end
    end
    
    # If JSON content was found, use its citations if available
    if json_content && json_content['citations'].is_a?(Array)
      json_content['citations'].each do |cite|
        cleaned_name = clean_document_name(cite.to_s)
        normalized_name = cleaned_name.downcase.strip
        unless seen_citations.include?(normalized_name)
          seen_citations << normalized_name
          citations << { title: cleaned_name, url: '#' }
        end
      end
    end
    
    { text: text, citations: citations, json_content: json_content }
  end
  
  def strip_citation_markers(text)
    # Remove citation markers like 【10:3†SR_THORAT_MILK_DPR.pdf】
    text.gsub(/【[^】]+】/, '').strip
  end
  
  def clean_document_name(name)
    return '' if name.nil?
    
    # Remove .pdf extension
    cleaned = name.to_s.gsub(/\.pdf$/i, '')
    
    # Remove citation markers if present (【】)
    cleaned = cleaned.gsub(/【|】/, '')
    
    # Remove citation numbers and symbols (10:3†)
    cleaned = cleaned.gsub(/\d+:\d+†/, '')
    cleaned = cleaned.gsub(/†/, '')
    
    # Replace underscores with spaces
    cleaned = cleaned.gsub(/_/, ' ')
    
    # Clean up multiple spaces
    cleaned = cleaned.gsub(/\s+/, ' ').strip
    
    # Capitalize words (title case)
    cleaned.split(' ').map(&:capitalize).join(' ')
  end
  
  def check_if_needs_web_search(content_text)
    return false unless content_text
    
    # Check if AI response indicates it couldn't find info in documents
    indicators = [
      "couldn't find",
      "not in the documents",
      "not available in",
      "would you like me to search",
      "search the internet",
      "result not found",
      "wish to search the internet"
    ]
    
    content_text_lower = content_text.downcase
    indicators.any? { |indicator| content_text_lower.include?(indicator) }
  end
end

