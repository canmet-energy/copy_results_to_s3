#!/usr/bin/env ruby

# Locate gems and make sure Ruby knows where they are so it can run this script.
gem_loc = '/usr/local/lib/ruby/gems/2.2.0/gems/'
gem_dirs = Dir.entries(gem_loc).select {|entry| File.directory? File.join(gem_loc,entry) and !(entry =='.' || entry == '..') }
gem_dirs.sort.each do |gem_dir|
  lib_loc = ''
  lib_loc = gem_loc + gem_dir + '/lib'
  $LOAD_PATH.unshift(lib_loc) unless $LOAD_PATH.include?(lib_loc)
end 

require 'bundler'
require 'securerandom'
require 'aws-sdk-s3'
require 'aws-sdk-lambda'
require 'json'
require 'zip'
require 'rest-client'

# Source copied and modified from https://github.com/rubyzip/rubyzip
# creates a zip of the given file and places the zipped file at the
# same location as the file
def zip_results(in_file:, out_file_name:)
  return false unless File.exist?(in_file)
  folder = File.dirname(in_file)
  input_filename = File.basename(in_file)
  zipfile_name = "#{folder}/#{out_file_name}.zip"
  puts "\n\tzipfile_name: #{zipfile_name}"
  ::Zip::File.open(zipfile_name, ::Zip::File::CREATE) do |zipfile|
    zipfile.get_output_stream(input_filename) do |out_file|
      out_file.write(File.open(in_file, 'rb').read)
    end
  end
  return zipfile_name
end

def invoke_lambda(osa_id:, osd_id:, file_id:)
  region = 'us-east-1'
  client = Aws::Lambda::Client.new(region: region)
  analysis_info = JSON.parse(RestClient.get("http://web:80/analyses/#{osa_id}.json", headers={}))
  if analysis_info.nil?
    analysis_json = {
        analysis_id: osa_id,
        analysis_name: 'no_name'
    }
  else
    analysis_json = {
        analysis_id: analysis_info['analysis']['_id'],
        analysis_name: analysis_info['analysis']['display_name']
    }
  end
  req_payload = {:analysis_id => osa_id, :datapoint_id => osd_id, :file_id => file_id, :analysis_json => analysis_json}
  payload = JSON.generate(req_payload)
  resp = client.invoke({
      function_name: 'extract_append_qaqc_error',
      invocation_type: 'Event',
      log_type: 'Tail',
      payload: payload
                       })
  return resp
end

#Get datapoint directory passed from worker finalization script.
out_dir = ARGV[0].to_s

#Set up s3.
region = 'us-east-1'
s3 = Aws::S3::Resource.new(region: region)
bucket_name = 'btapresultsbucket'
bucket = s3.bucket(bucket_name)

#Get current time and date (to use in logs)
time_obj = Time.new
curr_time = time_obj.year.to_s + "-" + time_obj.month.to_s + "-" + time_obj.day.to_s + "_" + time_obj.hour.to_s + ":" + time_obj.min.to_s + ":" + time_obj.sec.to_s + ":" + time_obj.usec.to_s

#Determine where osw file is
curr_dir = Dir.pwd
main_dir = curr_dir[0..-4]
out_file_loc = main_dir + out_dir + "/"
out_file = out_file_loc + "out.osw"

#Initialize some file locations
osa_id = ""
osd_id = ""
file_id = ""

#Determine if osw si there, if not then put an error on s3.
if File.file?(out_file)
  #Look through the osw and find the osa_id and osd_id
  File.open(out_file, "r") do |f|
    f.each_line do |line|
      if line.match(/   \"osa_id\" : \"/)
        osa_id = line[15..-4]
      elsif line.match(/   \"osd_id\" : \"/)
        osd_id = line[15..-4]
        end
    end
    #If either the osa_id or osd_id is missing then something is wrong so put an error on s3.
    if osa_id == "" || osd_id == ""
      file_id = "log_" + curr_time
      log_file_loc = "./" + file_id + "txt"
      log_file = File.open(log_file_loc, 'w')
      log_file.puts "Either could not find osa_id or osd_id in out.osw file."
      log_file.close
      log_obj = bucket.object("log/" + file_id)
      log_obj.upload_file(log_file_loc)
    else
      #If an osa_id and osw_id exist then assume the osw is good and put it in the s3 bucket with the name
      #'osa_id/osd_id.osw'.
      out_file_name = 'temp_out_osw'
      zip_file_loc = zip_results(in_file: out_file, out_file_name: out_file_name)
      file_id = osa_id + "/" + osd_id + ".zip"
      out_obj = bucket.object(file_id)
      while out_obj.exists? == false
        out_obj.upload_file(zip_file_loc)
      end
      File.delete(zip_file_loc) if File.exist?(zip_file_loc)
      lambda_resp = invoke_lambda(osa_id: osa_id, osd_id: osd_id, file_id: file_id)
    end
  end
else
  # Error create error log in s3 bucket if no osw is found.
  file_id = "log_" + curr_time
  log_file_loc = "./" + file_id + "txt"
  log_file = File.open(log_file_loc, 'w')
  log_file.puts "#{out_file} could not be found."
  log_file.close
  log_obj = bucket.object("log/" + file_id)
  log_obj.upload_file(log_file_loc)
end
