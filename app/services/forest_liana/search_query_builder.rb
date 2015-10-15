module ForestLiana
  class SearchQueryBuilder

    def initialize(resource, params)
      @resource = @records = resource
      @params = params
    end

    def perform
      @records = search_param
      @records = filter_param
      @records = associations_param
      @records = has_many_filter

      @records
    end

    def search_param
      if @params[:search]
        conditions = []

        @resource.columns.each_with_index do |column, index|
          if column.name == 'id'
            conditions << "#{@resource.table_name}.id =
              #{@params[:search].to_i}"
          elsif column.type == :string || column.type == :text
            conditions <<
              "#{column.name} ILIKE '%#{@params[:search].downcase}%'"
          end
        end

        @records = @resource.where(conditions.join(' OR '))
      end

      @records
    end

    def filter_param
      if @params[:filter]
        @params[:filter].each do |field, value|
          next if association?(field)

          operator, value = OperatorValueParser.parse(value)
          @records = @resource.where("#{field} #{operator} '#{value}'")
        end
      end

      @records
    end

    def association?(field)
      field = field.split(':').first if field.include?(':')
      @resource.reflect_on_association(field.to_sym).present?
    end

    def has_many_association?(field)
      field = field.split(':').first if field.include?(':')
      association = @resource.reflect_on_association(field.to_sym)

      association.try(:macro) === :has_many
    end

    def associations_param
      @records = belongs_to_associations_param
      @records = has_and_belongs_to_many_associations_param
    end

    def belongs_to_associations_param
      associations = @resource.reflect_on_all_associations(:belongs_to)

      associations.each do |association|
        name = association.name.to_s

        if @params[name + 'Id']
          @records = @resource.where("#{name.foreign_key} =
                                     #{@params[name + 'Id']}")
        end
      end

      @records
    end

    def has_and_belongs_to_many_associations_param
      associations = @resource
        .reflect_on_all_associations(:has_and_belongs_to_many)

      associations.each do |association|
        name = association.name.to_s

        if @params[name.singularize + 'Id']
          query = {}
          query[name] = { id: "#{@params[name.singularize + 'Id']}"}

          @records = @resource.includes(name).where(query)
        end
      end

      @records
    end

    def has_many_filter
      if @params[:filter]
        @params[:filter].each do |field, value|
          next unless has_many_association?(field)

          if field.include?(':')
            @records = has_many_subfield_filter(field, value)
          else
            @records = has_many_field_filter(field, value)
          end
        end
      end

      @records
    end

    def has_many_field_filter(field, value)
      association = @resource.reflect_on_association(field.to_sym)
      return if association.blank?

      operator, value = OperatorValueParser.parse(value)

      @records = @records
        .select("#{@resource.table_name}.*,
                COUNT(#{association.table_name}.id)
                #{association.table_name}_has_many_count")
        .joins(ArelHelpers.join_association(@resource, association.name,
                                            Arel::Nodes::OuterJoin))
        .group("#{@resource.table_name}.id")
        .having("COUNT(#{association.table_name}) #{operator} #{value}")
    end

    def has_many_subfield_filter(field, value)
      field, subfield = field.split(':')

      association = @resource.reflect_on_association(field.to_sym)
      return if association.blank?

      operator, value = OperatorValueParser.parse(value)

      @records = @records
        .select("#{@resource.table_name}.*,
                COUNT(#{association.table_name}.id)
                #{association.table_name}_has_many_count")
        .joins(ArelHelpers.join_association(@resource, association.name,
                                            Arel::Nodes::OuterJoin))
        .group("#{@resource.table_name}.id, #{association.table_name}.#{subfield}")
        .having("#{association.table_name}.#{subfield} #{operator} '#{value}'")
    end
  end
end
