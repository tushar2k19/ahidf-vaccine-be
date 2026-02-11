class Api::ChecklistController < ApplicationController
  include ApiResponseFormatter
  
  before_action :authenticate_user!
  
  # Base checklist items - same for all DPRs
  # Items 3 and 6 are conditional and will be inserted at their positions
  BASE_CHECKLIST_ITEMS = [
    "Project rationale and intended beneficiaries",                                    # Item 1
    "Alignment with AHIDF focus areas",                         # Item 2
    # Item 3: Plant and Machinery (conditional - inserted here if needed)
    "Socio-economic impact of the project",                                          # Item 4
    "Promoter equity contribution (minimum 10% of total project cost)",              # Item 5
    # Item 6: Technical equipment (conditional - inserted here if needed)
    "Means of finance and funding structure (including term loan details)",          # Item 7
    "Total project cost and cost breakdown (land, building, machinery, working capital, etc.)", # Item 8
    "Project type: new establishment or expansion of existing facility",             # Item 9
    "Project location: single location or multiple locations with complete details", # Item 10
    "Land documentation and ownership details (sale/lease/ownership deed)", # Item 11
    "Land ownership verification: confirm land documents are registered in applicant firm's name", # Item 12
    "Timeline for implementation with milestones",                                   # Item 13                                    # Item 16
    "Sustainability and financial viability analysis"                                # Item 17
  ].freeze

  # Conditional checklist items - added only for relevant DPRs
  CONDITIONAL_ITEMS = {
    # Item 3: Plant and Machinery - relevant for projects with manufacturing/processing
    plant_and_machinery: "List of Plant and Machinery including capacity details (number of birds/LLPD, MT/Day, MT/annum, etc.)",
    
    # Item 6: Technical equipment - relevant for dairy/breeding/animal husbandry projects
    technical_equipment: "Technical equipment specifications (sex-sorted semen station, AI gun, semen storage, cold chain infrastructure, and other specialized equipment with specifications and quantities)"
  }.freeze

  # Documents that require Plant and Machinery item (item 3)
  # Add document names here if they need plant and machinery details
  DOCUMENTS_WITH_PLANT_MACHINERY = [
    "sr_thorat_milk_dpr.pdf",
    "singhania_milk_dpr.pdf",
    "sikandarpur_industrial_dpr.pdf",
    "de_heus_animal_nutrition_dpr.pdf",
    "balaji_hatcherie_poultry_dpr.pdf"
  ].freeze

  # Documents that require Technical Equipment item (item 6)
  # Add document names here if they need technical equipment details
  DOCUMENTS_WITH_TECHNICAL_EQUIPMENT = [
    "sr_thorat_milk_dpr.pdf",
    "singhania_milk_dpr.pdf",
    "balaji_hatcherie_poultry_dpr.pdf"
    # Add "de_heus_animal_nutrition_dpr.pdf" if it needs technical equipment
  ].freeze

  # Default checklist items (fallback) - same as base for consistency
  DEFAULT_CHECKLIST_ITEMS = BASE_CHECKLIST_ITEMS.dup.freeze
  
  # GET /api/checklist/defaults
  # Returns unified checklist items with conditional items based on document type
  def defaults
    document_name = params[:document_name]
    
    if document_name.present?
      # Normalize document name for lookup
      normalized_doc_name = normalize_doc_name(document_name)
      
      # Start with base checklist items
      checklist_items = BASE_CHECKLIST_ITEMS.dup
      
      # Add conditional items based on document type
      # Item 3: Plant and Machinery - insert at position 2 (after item 2, before item 4)
      if DOCUMENTS_WITH_PLANT_MACHINERY.include?(normalized_doc_name)
        checklist_items.insert(2, CONDITIONAL_ITEMS[:plant_and_machinery])
      end
      
      # Item 6: Technical Equipment - insert at position 5 (after item 5)
      # Adjust position if Plant and Machinery was added (it shifts everything by 1)
      if DOCUMENTS_WITH_TECHNICAL_EQUIPMENT.include?(normalized_doc_name)
        insert_position = DOCUMENTS_WITH_PLANT_MACHINERY.include?(normalized_doc_name) ? 6 : 5
        checklist_items.insert(insert_position, CONDITIONAL_ITEMS[:technical_equipment])
      end
      
      render_success(
        {
          checklist_items: checklist_items,
          total_items: checklist_items.length,
          document_name: document_name,
          is_document_specific: true,
          conditional_items_added: {
            plant_and_machinery: DOCUMENTS_WITH_PLANT_MACHINERY.include?(normalized_doc_name),
            technical_equipment: DOCUMENTS_WITH_TECHNICAL_EQUIPMENT.include?(normalized_doc_name)
          }
        },
        message: "Checklist items retrieved successfully"
      )
    else
      # Return base items if no document specified
      render_success(
        {
          checklist_items: BASE_CHECKLIST_ITEMS,
          total_items: BASE_CHECKLIST_ITEMS.length,
          document_name: nil,
          is_document_specific: false
        },
        message: "Default checklist items retrieved successfully"
      )
    end
  end
  
  # POST /api/checklist/analyze
  # Processes checklist items against selected documents
  def analyze
    Rails.logger.info "=== Checklist Analysis Request Started ==="
    Rails.logger.info "User ID: #{current_user&.id}"
    Rails.logger.info "Request params: #{params.inspect}"
    
    begin
      # Validate request parameters
      validation_result = validate_analyze_params
      if validation_result[:error]
        Rails.logger.error "Validation failed: #{validation_result[:error]}"
        return render_error(validation_result[:error], :unprocessable_entity)
      end
      
      document_names = validation_result[:document_names]
      checklist_items = validation_result[:checklist_items]
      
      Rails.logger.info "Validated documents: #{document_names}"
      Rails.logger.info "Validated checklist items: #{checklist_items.length} items"
      
      # Process checklist with OpenAI
      Rails.logger.info "Starting OpenAI checklist analysis..."
      checklist_results = OpenaiService.new.analyze_checklist(
        document_names: document_names,
        checklist_items: checklist_items
      )
      
      Rails.logger.info "OpenAI analysis completed successfully"
      Rails.logger.info "Results count: #{checklist_results.length}"
      
      # Format response
      response_data = {
        checklist_results: checklist_results,
        analyzed_documents: document_names,
        total_items: checklist_items.length,
        analysis_timestamp: Time.current.iso8601
      }
      
      Rails.logger.info "=== Checklist Analysis Request Completed Successfully ==="
      render_success(
        response_data,
        message: "Checklist analysis completed successfully"
      )
      
    rescue => e
      Rails.logger.error "=== Checklist Analysis Request Failed ==="
      Rails.logger.error "Error: #{e.message}"
      Rails.logger.error "Backtrace: #{e.backtrace.first(5).join("\n")}"
      
      error_message = case e.message
      when /timeout/i
        "Analysis timed out. Please try with fewer checklist items or documents."
      when /rate limit/i
        "API rate limit exceeded. Please try again in a few minutes."
      when /OpenAI/i
        "AI service error. Please try again later."
      else
        "An error occurred during analysis. Please try again."
      end
      
      render_error(error_message, :internal_server_error)
    end
  end
  
  private
  
  def validate_analyze_params
    # Validate document_names parameter
    document_names = params[:document_names]
    if document_names.blank? || !document_names.is_a?(Array)
      return { error: "document_names parameter is required and must be an array" }
    end
    
    if document_names.empty?
      return { error: "At least one document must be selected" }
    end
    
    # Validate document names (accept both space and underscore variants, case-insensitive)
    # Currently using 5 AHIDF documents: SR Thorat Milk, Singhania Milk, Sikandarpur Industrial, De Heus Animal Nutrition, and Balaji Hatcherie Poultry
    valid_documents = [
      "SR_THORAT_MILK_DPR.pdf",
      "SINGHANIA_MILK_DPR.pdf",
      "Sikandarpur_Industrial_DPR.pdf",
      "De_Heus_Animal_Nutrition_DPR.pdf",
      "BALAJI_HATCHERIE_POULTRY_DPR.pdf"
    ]

    valid_normalized = valid_documents.map { |n| normalize_doc_name(n) }.to_set
    invalid_docs = document_names.reject { |name| valid_normalized.include?(normalize_doc_name(name)) }
    if invalid_docs.any?
      return { error: "Invalid document names: #{invalid_docs.join(', ')}" }
    end
    
    # Validate checklist_items parameter
    checklist_items = params[:checklist_items]
    if checklist_items.blank?
      # Use default items if none provided
      checklist_items = DEFAULT_CHECKLIST_ITEMS
    elsif !checklist_items.is_a?(Array)
      return { error: "checklist_items parameter must be an array" }
    elsif checklist_items.empty?
      return { error: "At least one checklist item is required" }
    elsif checklist_items.length > 15
      return { error: "Maximum 15 checklist items allowed" }
    end
    
    # Validate individual checklist items
    checklist_items.each_with_index do |item, index|
      if item.blank? || !item.is_a?(String)
        return { error: "Checklist item #{index + 1} must be a non-empty string" }
      end
      if item.length > 500
        return { error: "Checklist item #{index + 1} is too long (maximum 200 characters)" }
      end
    end
    
    {
      document_names: document_names,
      checklist_items: checklist_items
    }
  end

  # Normalize a document name to a canonical form for validation
  def normalize_doc_name(name)
    str = name.to_s.strip
    # Ensure extension is present and unified
    str += '.pdf' unless str.downcase.end_with?('.pdf')
    str = str.gsub(/\s+/, '_')
    str.downcase
  end
end
