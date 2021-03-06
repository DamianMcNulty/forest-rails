module ForestLiana
  class ResourcesGetter
    def initialize(resource, params)
      @resource = resource
      @params = params
      @field_names_requested = field_names_requested
    end

    def field_names_requested
      return nil unless @params[:fields] && @params[:fields][@resource.table_name]

      associations_for_query = []

      # NOTICE: Populate the necessary associations for filters
      if @params[:filter]
        @params[:filter].each do |field, values|
          if field.include? ':'
            associations_for_query << field.split(':').first.to_sym
          end
        end
      end

      if @params[:sort] && @params[:sort].include?('.')
        associations_for_query << @params[:sort].split('.').first.to_sym
      end

      field_names = @params[:fields][@resource.table_name].split(',')
                                              .map { |name| name.to_sym }
      field_names | associations_for_query
    end

    def perform
      @records = @resource.unscoped.eager_load(includes)
      @records = search_query
      @sorted_records = sort_query
    end

    def records
      @sorted_records.select(select).offset(offset).limit(limit).to_a
    end

    def count
      @records.count
    end

    def includes
      includes = SchemaUtils.one_associations(@resource)
        .select { |association| SchemaUtils.model_included?(association.klass) }
        .map(&:name)

      if @field_names_requested
        includes & @field_names_requested
      else
        includes
      end
    end

    private

    def search_query
      SearchQueryBuilder.new(@records, @params, includes).perform
    end

    def sort_query
      if @params[:sort]
        @params[:sort].split(',').each do |field|
          order = detect_sort_order(@params[:sort])
          field.slice!(0) if order == :desc

          field = detect_reference(field)
          if field.index('.').nil?
            @records = @records
              .order("#{@resource.table_name}.#{field} #{order.upcase}")
          else
            @records = @records.order("#{field} #{order.upcase}")
          end
        end
      elsif @resource.column_names.include?('created_at')
        @records = @records.order("#{@resource.table_name}.created_at DESC")
      elsif @resource.column_names.include?('id')
        @records = @records.order("#{@resource.table_name}.id DESC")
      end

      @records
    end

    def detect_sort_order(field)
      return (if field[0] == '-' then :desc else :asc end)
    end

    def detect_reference(param)
      ref, field = param.split('.')

      if ref && field
        association = @resource.reflect_on_all_associations
          .find {|a| a.name == ref.to_sym }

        if association
          "\"#{association.table_name}\".\"#{field}\""
        else
          param
        end
      else
        param
      end
    end

    def association?(field)
      @resource.reflect_on_association(field.to_sym).present?
    end

    def select
      column_names = @resource.column_names.map { |name| name.to_sym }
      if @field_names_requested
        column_names & @field_names_requested
      else
        column_names
      end
    end

    def offset
      return 0 unless pagination?

      number = @params[:page][:number]
      if number && number.to_i > 0
        (number.to_i - 1) * limit
      else
        0
      end
    end

    def limit
      return 10 unless pagination?

      if @params[:page][:size]
        @params[:page][:size].to_i
      else
        10
      end
    end

    def pagination?
      @params[:page] && @params[:page][:number]
    end

  end
end
