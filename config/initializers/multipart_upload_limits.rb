file_limit = ENV.fetch("GIS_MULTIPART_FILE_LIMIT", 100_001).to_i
total_part_limit = ENV.fetch(
  "GIS_MULTIPART_TOTAL_PART_LIMIT",
  file_limit.positive? ? file_limit + 100 : 0
).to_i

Rack::Utils.multipart_file_limit = file_limit
Rack::Utils.multipart_part_limit = file_limit if Rack::Utils.respond_to?(:multipart_part_limit=)
Rack::Utils.multipart_total_part_limit = total_part_limit
