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
error_col = []

qaqc_temp_file = './qaqc_temp.json'
qaqc_temp_col = './qaqc_col.json'
qaqc_col = []

#Go through all of the objects in the s3 bucket searching for the qaqc.json and error.json objects related the current
#analysis.
bucket.objects.each do |bucket_info|
  unless (/#{analysis_id}/ =~ bucket_info.key.to_s).nil?
    #Remove the / characters with _ to avoid regex problems
    replacekey = bucket_info.key.to_s.gsub(/\//, '_')
    #Search for objects with the current analysis id that have error and .json in them and collate them into one big
    #collated error.json object and push it to s3.
    unless (/error_/ =~ replacekey.to_s).nil? || (/\.json/ =~ replacekey.to_s).nil?
      #If you find a datapoint error file try downloading it and adding the information to the error_col array of hashes.
      error_index = 0
      while error_index < 10
        puts error_index
        error_index += 1
        bucket_info.download_file(error_temp_file)
        error_index = 11 if File.exist?(error_temp_file)
      end
      if File.exist?(error_temp_file)
        error_json = JSON.parse(File.read(error_temp_file))
        error_json.each do |error_out|
          error_col << error_out
        end
        # Get rid of the datapoint error.json file that was just downloaded.
        File.delete(error_temp_file)
      else
        puts "Could not download #{bucket_info.key}"
      end
    end
    #Search for objects with the current analysis id that have qaqc and .json in them and collate them into one big
    #collated error.json object and push it to s3.
    unless (/qaqc_/ =~ replacekey.to_s).nil? || (/\.json/ =~ replacekey.to_s).nil?
      #If you find a datapoint qaqc file try downloading it and adding the information to the qaqc_col array of hashes.
      qaqc_index = 0
      while qaqc_index < 10
        puts qaqc_index
        qaqc_index += 1
        bucket_info.download_file(qaqc_temp_file)
        qaqc_index = 11 if File.exist?(qaqc_temp_file)
      end
      if File.exist?(qaqc_temp_file)
        qaqc_json = JSON.parse(File.read(qaqc_temp_file))
        qaqc_json.each do |qaqc_out|
          qaqc_col << qaqc_out
        end
        # Get rid of the datapoint qaqc.json file that was just downloaded.
        File.delete(qaqc_temp_file)
      else
        puts "Could not download #{bucket_info.key}"
      end
    end
  end
end
#Generated a collated error.json file using the collated array of datapoint error hashes.
#Create an s3 object and push the collated error.json file to it.
File.open(error_temp_col,"w") {|each_file| each_file.write(JSON.pretty_generate(error_col))}
error_out_id = analysis_id + "/" + "error_col.json"
error_out_obj = bucket.object(error_out_id)
while error_out_obj.exists? == false
  error_out_obj.upload_file(error_temp_col)
end

#Generated a collated qaqc.json file using the collated array of datapoint qaqc hashes.
#Create an s3 object and push the collated qaqc.json file to it (this makes the simulations.json for the analysis).
File.open(qaqc_temp_col,"w") {|each_file| each_file.write(JSON.pretty_generate(qaqc_col))}
qaqc_out_id = analysis_id + "/" + "simulations.json"
qaqc_out_obj = bucket.object(qaqc_out_id)
while qaqc_out_obj.exists? == false
  qaqc_out_obj.upload_file(qaqc_temp_col)
end

#Delete the collated error.json and qaqc.json files.
File.delete(error_temp_col)
File.delete(qaqc_temp_col)
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