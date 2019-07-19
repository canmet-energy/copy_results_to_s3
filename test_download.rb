require 'bundler'
require 'aws-sdk-s3'
require 'json'

analysis_id = ARGV[0].to_s

region = 'us-east-1'
s3 = Aws::S3::Resource.new(region: region)
bucket_name = 'btapresultsbucket'
bucket = s3.bucket(bucket_name)

error_temp_file = './error_temp.json'
error_temp_col = './error_col.json'
error_full = []
bucket.objects.each do |bucket_info|
  unless (/#{analysis_id}/ =~ bucket_info.key.to_s).nil?
    replacekey = bucket_info.key.to_s.gsub(/\//, '_')
    unless (/error_/ =~ replacekey.to_s).nil? || (/\.json/ =~ replacekey.to_s).nil?
      puts bucket_info.key.to_s
      for index in 0..9
        bucket_info.download_file(error_temp_file)
        index = 10 if File.exist?(error_temp_file)
      end
      if File.exist?(error_temp_file)
        error_json = JSON.parse(File.read(error_temp_file))
        error_json.each do |error_out|
          error_full << error_out
        end
        File.delete(error_temp_file)
      else
        puts "Could not download #{bucket_info.key}"
      end
    end
  end
end
File.open(error_temp_col,"w") {|each_file| each_file.write(JSON.pretty_generate(error_full))}
out_id = analysis_id + "/" + "error_col.json"
out_obj = bucket.object(out_id)
while out_obj.exists? == false
  out_obj.upload_file(error_temp_col)
end
#puts analysis_id

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