require 'bundler'
require 'aws-sdk-s3'
require 'json'

analysis_id = ARGV[0].to_s

region = 'us-east-1'
s3 = Aws::S3::Resource.new(region: region)
bucket_name = 'btapresultsbucket'
bucket = s3.bucket(bucket_name)

bucket.objects.each do |bucket_info|

  unless (/#{analysis_id}/ =~ bucket_info.key.to_s).nil?
    replacekey = bucket_info.key.to_s.gsub(/\//, '_')
    #puts replacekey.to_s
    unless (/qaqc/ =~ replacekey.to_s).nil? || (/\.json/ =~ replacekey.to_s).nil?
      puts bucket_info.key.to_s
    end
  end

=begin
  unless (/#{analysis_id}/ =~ bucket_info.key.to_s).nil? and (/qaqc/ =~ bucket_info.key.to_s).nil? || (/\.json/ =~ bucket_info.key.to_s).nil?
    puts bucket_info.key
    puts "analysis_id:"
    puts /#{analysis_id}/ =~ bucket_info.key.to_s
    puts "qaqc:"
    puts /qaqc/ =~ bucket_info.key.to_s
    puts "json:"
    puts /json/ =~ bucket_info.key.to_s
  end
=end
end
puts analysis_id

#res_path = "/mnt/openstudio/server/assets/"
#res_file = "results." + analysis_id + ".zip"
#res_file_path = res_path + res_file

#time_obj = Time.new
#curr_time = time_obj.year.to_s + "-" + time_obj.month.to_s + "-" + time_obj.day.to_s + "_" + time_obj.hour.to_s + ":" + time_obj.min.to_s + ":" + time_obj.sec.to_s + ":" + time_obj.usec.to_s
=begin
if File.file?(res_file_path)
  file_id = analysis_id + "/" + "results.zip"
  out_obj = bucket.object(file_id)
  resp = []
  while out_obj.exists? == false
    out_obj.upload_file(res_file_path)
  end
else
  file_id = "log_" + curr_time
  log_file_loc = "./" + file_id + ".txt"
  log_file = File.open(log_file_loc, 'w')
  log_file.puts "#{res_file_path} could not be found."
  log_file.close
  log_obj = bucket.object("log/" + file_id)
  log_obj.upload_file(log_file_loc)
end
=end