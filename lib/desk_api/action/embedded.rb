module DeskApi
  module Action
    module Embedded
    private
      def setup_embedded(entries)
        @records = entries.map do |record|
          resource(record._links.self['class']).new(client, record, true)
        end
      end
    end
  end
end