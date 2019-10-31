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

def invoke_lambda(osa_id:, bucket_name:, object_keys:, analysis_json:, region:)
  puts 'Object keys passed to invoke_lambda method:'
  puts object_keys
  client = Aws::Lambda::Client.new(region: region, http_read_timeout: 1800)
  resp_col = []
  block_size = 500.0
  cycles = (object_keys.size/block_size)
  for cycle_count in 0..cycles.to_i
    count_left = cycles - cycle_count
    sub_start = (cycle_count*block_size).round(0)
    count_left >= 1 ? sub_end = sub_start + (block_size.to_i - 1) : sub_end = sub_start + (count_left*block_size).round(0) - 1
    object_subkeys = object_keys[sub_start..sub_end]
    puts "Object keys passed to compile_sub_BTAP_results lambda function:"
    puts object_subkeys
    puts "object_subkeys size:"
    puts object_subkeys.size
    req_payload = {
        osa_id: osa_id,
        bucket_name: bucket_name,
        object_keys: object_subkeys,
        cycle_count: cycle_count,
        region: region,
        analysis_json: analysis_json
    }
    payload = JSON.generate(req_payload)
    resp = client.invoke({
                             function_name: 'compile_multzip_sub_BTAP_results',
                             invocation_type: 'RequestResponse',
                             log_type: 'Tail',
                             payload: payload
                         })
    puts "Compile sub BTAP results lambda function response:"
    puts JSON.parse(resp.payload.string)
    resp_col << resp
  end
  return resp_col, cycles
end

# This calls a lambda function which collects the names of all of the objects in an s3 bucket with the analysis_id in
# the name and that have .zip at the end.
def get_analysis_objects(osa_id:, bucket_name:, analysis_json:, region:)
  client = Aws::Lambda::Client.new(region: region, http_read_timeout: 1800)
  req_payload = {
      osa_id: osa_id,
      bucket_name: bucket_name,
      region: region,
      analysis_name: analysis_json[:analysis_name]
  }
  payload = JSON.generate(req_payload)
  resp = client.invoke({
                           function_name: 'get_analysis_object_names_s3',
                           invocation_type: 'RequestResponse',
                           log_type: 'Tail',
                           payload: payload
                       })
  puts "Get analysis objects lambda function response:"
  ret_status = resp.status_code
  ret_objects = []
  if ret_status == 200
    object_name = analysis_json[:analysis_name] + '_' + osa_id + '/' + 'datapoint_ids.json'
    ret_objects.concat(get_s3_stream(file_id: object_name, bucket_name: bucket_name, region: region))
  end
  return ret_objects
end

def col_res(osa_id:, bucket_name:, cycles:, file_pref:, analysis_json:, region:)
  client = Aws::Lambda::Client.new(region: region, http_read_timeout: 1800)
  req_payload = {
      osa_id: osa_id,
      bucket_name: bucket_name,
      cycle_count: cycles,
      append_tag: file_pref,
      region: region,
      analysis_json: analysis_json
  }
  puts "Ammend BTAP results payload:"
  puts req_payload
  payload = JSON.generate(req_payload)
  resp = client.invoke({
                           function_name: 'append_BTAP_results',
                           invocation_type: 'RequestResponse',
                           log_type: 'Tail',
                           payload: payload
                       })
  puts "Ammend BTAP results lambda function response:"
  ret_objects = JSON.parse(resp.payload.string)
  puts ret_objects
  return ret_objects
end

def get_analysis_info(osa_id:)
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
  return analysis_json
end

def get_s3_stream(file_id:, bucket_name:, region:)
  s3_res = Aws::S3::Resource.new(region: region)
  bucket = s3_res.bucket(bucket_name)
  ret_bucket = bucket.object(file_id)
  if ret_bucket.exists?
    s3_cli = Aws::S3::Client.new(region: region)
    return_data = JSON.parse(s3_cli.get_object(bucket: bucket_name, key: file_id).body.read)
  else
    return_data = []
  end
  return return_data
end

def loc_col_res(osa_id:, bucket_name:, append_tag:, cycle_count:, analysis_name:, region:)
  s3_cli = Aws::S3::Client.new(region: region)
  res_comp = "["
  for result_num in 1..cycle_count
    res_key = analysis_name + '_' + osa_id + '/' + append_tag + '_' + result_num.to_s + '.json'
    res_comp << s3_cli.get_object(bucket: bucket_name, key: res_key).body.read[1..-2] + ','
  end
  res_comp[-1] = ']'
  out_key = analysis_name + '_' + osa_id + '/' + append_tag + '.json'
  resp = s3_cli.put_object({
                               body: res_comp,
                               bucket: bucket_name,
                               key: out_key
                           })
  return resp
end

#Get the analysis_id from the server finalization script.
input_arguments = ARGV
analysis_id = input_arguments[0].to_s
bucket_name = input_arguments[1].to_s
aws_region = input_arguments[2].to_s
proc_local = input_arguments[3].to_s

#Get current time and date (to use in logs)
time_obj = Time.new
curr_time = time_obj.year.to_s + "-" + time_obj.month.to_s + "-" + time_obj.day.to_s + "_" + time_obj.hour.to_s + ":" + time_obj.min.to_s + ":" + time_obj.sec.to_s + ":" + time_obj.usec.to_s

#Determine if an object with the analysis_id exists in s3 (thus the analysis has begun).  If something is there run the
#lambda function.  Otherwise put an error log up saying that the analysis has not started.  This check is required
#because OpenStudio_server 2.8.1 run the server finalization script at the start and end of the analysis rather than
#just at the end.
analysis_json = get_analysis_info(osa_id: analysis_id)
object_keys = get_analysis_objects(osa_id: analysis_id, bucket_name: bucket_name, analysis_json: analysis_json, region: aws_region)
if object_keys.empty?
  s3 = Aws::S3::Resource.new(region: aws_region)
  bucket = s3.bucket(bucket_name)
  file_id = "error_coll_log_" + curr_time
  log_file_contents = "No analysis data could be found in folder with analysis ID: #{analysis_id}; and analysis name: #{analysis_json[:analysis_name]}."
  log_obj = bucket.object("log/" + file_id)
  log_obj.put(body: log_file_contents)
else
  # If an s3 object with the analysis_id exists then first run the lambda function which extracts the qaqc.json file
  # form the result.zip files and combines them into simulations_#.json files in sets of 500.  Once successfully
  # completed them combine the simulations_#.json files into a final simulations.json file and put it on s3.  If
  # proc_local is true this is done on the EC2 instance, if it is false this is done via a lambda function.  The lambda
  # function will use less processing (and data transfer) on the EC2 instance which may reduce the likelyhood of data
  # transfer errors.  However, the lambda function is limited to 3GB of memory and can only run for up to 15 minutes.
  col_lambda_resp, cycles = invoke_lambda(osa_id: analysis_id, bucket_name: bucket_name, object_keys: object_keys, analysis_json: analysis_json, region: aws_region)
  #Need to fix this so it actually checks for a response.
  if col_lambda_resp.empty? || col_lambda_resp[0].nil? || cycles.nil?
    "There was an error in the lambda function which compiles qaqc.json files into simulations files."
  else
    ammend_cycles = cycles.to_i + 1
    col_res_resp_all = []
    file_prefix = ['simulations']
    if proc_local.downcase == "false"
      # Currently this only appends simulations_# files but you could modify the compile_multzip_sub_BTAP_results lambda
      # funciton to append other files in the results.zip files and then compile those here too (as was originally done
      # with the eplus error files).
      file_prefix.each do |file_pref|
        puts file_pref
        col_res_resp = col_res(osa_id: analysis_id, bucket_name: bucket_name, cycles: ammend_cycles, file_pref: file_pref, analysis_json: analysis_json, region: aws_region)
        col_res_resp_all << col_res_resp
      end
    else
      file_prefix.each do |file_pref|
        puts file_pref
        col_res_resp = loc_col_res(osa_id: analysis_id, bucket_name: bucket_name, append_tag: file_pref, cycle_count: ammend_cycles, analysis_name: analysis_json[:analysis_name], region: aws_region)
        col_res_resp_all << col_res_resp
      end
    end
  end
end
