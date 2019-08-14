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
require 'aws-sdk-s3'
require 'aws-sdk-lambda'
require 'json'
require 'rest-client'

def invoke_lambda(osa_id:, bucket_name:)
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
  req_payload = {
      osa_id: osa_id,
      bucket_name: bucket_name,
      analysis_json: analysis_json
  }
  payload = JSON.generate(req_payload)
  resp = client.invoke({
      function_name: 'compile_BTAP_results',
      invocation_type: 'RequestResponse',
      log_type: 'Tail',
      payload: payload
                       })
  puts "Lambda function response:"
  puts JSON.parse(resp.payload.string)
  return resp
end

# This calls a lambda function which collects the names of all of the objects in an s3 bucket with the analysis_id in
# the name and that have .zip at the end.
def get_analysis_objects(osa_id:, bucket_name:)
  region = 'us-east-1'
  client = Aws::Lambda::Client.new(region: region)
  req_payload = {
      osa_id: osa_id,
      bucket_name: bucket_name
  }
  payload = JSON.generate(req_payload)
  resp = client.invoke({
                           function_name: 'get_analysis_object_names',
                           invocation_type: 'RequestResponse',
                           log_type: 'Tail',
                           payload: payload
                       })
  puts "Lambda function response:"
  ret_objects = JSON.parse(resp.payload.string)
  puts ret_objects
  return ret_objects
end

#Get the analysis_id from the server finalization script.
input_arguments = ARGV
analysis_id = input_arguments[0].to_s
bucket_name = input_arguments[1].to_s

#Get current time and date (to use in logs)
time_obj = Time.new
curr_time = time_obj.year.to_s + "-" + time_obj.month.to_s + "-" + time_obj.day.to_s + "_" + time_obj.hour.to_s + ":" + time_obj.min.to_s + ":" + time_obj.sec.to_s + ":" + time_obj.usec.to_s

#Determine if an object with teh analysis_id exists in s3 (thus the analysis has begun).  If something is there run the
#lambda function.  Otherwise put an error log up saying that the analysis has not started.  This check is required
#because OpenStudio_server 2.8.1 run the server finalization script at the start and end of the analysis rather than
#just at the end.
analysis_objects = get_analysis_objects(osa_id: analysis_id, bucket_name: bucket_name)
if analysis_objects.empty?
  region = 'us-east-1'
  s3 = Aws::S3::Resource.new(region: region)
  bucket = s3.bucket(bucket_name)
  file_id = "error_coll_log_" + curr_time
  log_file_contents = "No analysis data could be found."
  log_obj = bucket.object("log/" + file_id)
  log_obj.put(body: log_file_contents)
else
  lambda_resp = invoke_lambda(osa_id: analysis_id, bucket_name: bucket_name)
end