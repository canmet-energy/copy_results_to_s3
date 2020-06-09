#!/usr/bin/env ruby

# *******************************************************************************
# Copyright (c) 2008-2019, Natural Resources Canada
# All rights reserved.
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# (1) Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# (2) Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# (3) Neither the name of the copyright holder nor the names of any contributors
# may be used to endorse or promote products derived from this software without
# specific prior written permission from the respective party.
#
# (4) Other than as required in clauses (1) and (2), distributions in any form
# of modifications or other derivative works may not use the "BTAP"
# trademark, or any other confusingly similar designation without
# specific prior written permission from Natural Resources Canada.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER(S) AND ANY CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER(S), ANY CONTRIBUTORS, THE
# CANADIAN FEDERAL GOVERNMENT, OR NATURAL RESOURCES CANADA, NOR ANY OF
# THEIR EMPLOYEES, BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
# OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# *******************************************************************************

#Get arguments from the server finalization script.
input_arguments = ARGV
analysis_id = input_arguments[0].to_s
bucket_name = input_arguments[1].to_s
aws_s3_region = input_arguments[2].to_s
proc_local = input_arguments[3].to_s
aws_lambda_region = input_arguments[4].to_s
gem_loc = input_arguments[5].to_s

# Locate gems and make sure Ruby knows where they are so it can run this script.
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
require 'zip'

def invoke_lambda(osa_id:, bucket_name:, object_keys:, analysis_json:, lambda_region:, s3_region:)
  puts 'Object keys passed to invoke_lambda method:'
  puts object_keys
  client = Aws::Lambda::Client.new(region: lambda_region, http_read_timeout: 1800)
  resp_col = []
  block_size = 500.0
  cycles = (object_keys.size.to_f/block_size)
  equal_num = false
  if (cycles.round(7) - cycles.round(7).truncate.to_f) == 0.0
    cycles = cycles.round(7) - 1.0
    equal_num = true
  end
  for cycle_count in 0..cycles.to_i
    count_left = cycles - cycle_count
    sub_start = (cycle_count*block_size).round(0)
    count_left >= 1 ? sub_end = sub_start + (block_size.to_i - 1) : sub_end = sub_start + (count_left*block_size).round(0) - 1
    if equal_num == true
      count_left >= 1 ? sub_end = sub_start + (block_size.to_i - 1) : sub_end = sub_start + block_size.round(0).to_i - 1
    end
    object_subkeys = object_keys[sub_start..sub_end]
    puts ""
    puts "Object keys passed to compile_multizip_sub_BTAP_results lambda function:"
    puts object_subkeys
    puts "object_subkeys size:"
    puts object_subkeys.size
    req_payload = {
        osa_id: osa_id,
        bucket_name: bucket_name,
        object_keys: object_subkeys,
        cycle_count: cycle_count,
        region: s3_region,
        analysis_json: analysis_json
    }
    payload = JSON.generate(req_payload)
    resp = client.invoke({
                             function_name: 'compile_multizip_sub_BTAP_results',
                             invocation_type: 'RequestResponse',
                             log_type: 'Tail',
                             payload: payload
                         })
    puts "compile_multizip_sub_BTAP results lambda function response:"
    puts JSON.parse(resp.payload.string)
    resp_col << resp
  end
  return resp_col, cycles
end

# This calls a lambda function which collects the names of all of the objects in an s3 bucket with the analysis_id in
# the name and that have .zip at the end.
def get_analysis_objects(osa_id:, bucket_name:, analysis_json:, lambda_region:, s3_region:)
  client = Aws::Lambda::Client.new(region: lambda_region, http_read_timeout: 1800)
  req_payload = {
      osa_id: osa_id,
      bucket_name: bucket_name,
      region: s3_region,
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
    ret_objects.concat(get_s3_stream(file_id: object_name, bucket_name: bucket_name, region: s3_region))
  end
  return ret_objects
end

def col_res(osa_id:, bucket_name:, cycles:, file_pref:, analysis_json:, lambda_region:, s3_region:)
  client = Aws::Lambda::Client.new(region: lambda_region, http_read_timeout: 1800)
  req_payload = {
      osa_id: osa_id,
      bucket_name: bucket_name,
      cycle_count: cycles,
      append_tag: file_pref,
      region: s3_region,
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

def collate_output_locally(osa_id: , bucket_name:, append_tags:, analysis_name:, region:, object_keys:, search_file:)
  missing_files = []
  col_data = []
  ret_status = []
  object_keys.each do |object_key|
    zip_info = get_file_s3(file_id: object_key, bucket_name: bucket_name, region: region)
    if zip_info[:exist] == false
      missing_files << {
          object_key: object_key,
          message: "Could not retrieve zip file."
      }
      next
    end
    ret_data = unzip_files(zip_name: zip_info[:file], search_name: search_file)
    if ret_data[:status] == false
      missing_files << {
          object_key: object_key,
          message: "No qaqc.json file present in zip file."
      }
      File.delete(zip_info[:file])
      next
    else
      ret_data[:out_info].each do |ret_dp|
        col_data << JSON.parse(ret_dp)
      end
      File.delete(zip_info[:file])
    end
  end
  s3_object_tag_start = analysis_name + '_' + osa_id + '/'
  unless missing_files.empty?
    file_id = s3_object_tag_start + 'missing_files.json'
    ret_status << put_data_s3(file_id: file_id, bucket_name: bucket_name, data: missing_files, region: region)
  end
  file_id = s3_object_tag_start + append_tags[0] + '.json'
  ret_status << put_data_s3(file_id: file_id, bucket_name: bucket_name, data: col_data, region: region)
  return ret_status
end

def get_file_s3(file_id:, bucket_name:, region:)
  s3 = Aws::S3::Resource.new(region: region)
  bucket = s3.bucket(bucket_name)
  ret_bucket = bucket.object(file_id)
  download_loc = "/tmp/out.zip"
  if File.exist?(download_loc)
    File.delete(download_loc)
  end
  if ret_bucket.exists?
    #If you find an osw.zip file try downloading it and adding the information to the error_col array of hashes.
    zip_index = 0
    while zip_index < 10
      zip_index += 1
      ret_bucket.download_file(download_loc)
      zip_index = 11 if File.exist?(download_loc)
    end
    if zip_index == 10
      return {exist: false, file: nil}
    else
      return {exist: true, file: download_loc}
    end
  else
    return {exist: false, file: nil}
  end
end

# Source copied and modified from https://github.com/rubyzip/rubyzip.
# This extracts the data from a zip file that presumably contains a json file.  It returns the contents of that file in
# an array of hashes (if there were multiple files in the zip file.)
def unzip_files(zip_name:, search_name: nil)
  output = {
      status: false,
      out_info: []
  }
  Zip::File.open(zip_name) do |zip_file|
    zip_file.each do |entry|
      if search_name.nil?
        output[:status] = true
        content = entry.get_input_stream.read
        output[:out_info] << content
      else
        if entry.name == search_name
          output[:status] = true
          content = entry.get_input_stream.read
          output[:out_info] << content
        end
      end
    end
  end
  return output
end

def put_data_s3(file_id:, bucket_name:, data:, region:)
  out_data = JSON.generate(data)
  s3 = Aws::S3::Resource.new(region: region)
  bucket = s3.bucket(bucket_name)
  out_obj = bucket.object(file_id)
  out_obj.put(body: out_data)
end

#Get current time and date (to use in logs)
time_obj = Time.new
curr_time = time_obj.year.to_s + "-" + time_obj.month.to_s + "-" + time_obj.day.to_s + "_" + time_obj.hour.to_s + ":" + time_obj.min.to_s + ":" + time_obj.sec.to_s + ":" + time_obj.usec.to_s

#Determine if an object with the analysis_id exists in s3 (thus the analysis has begun).  If something is there run the
#lambda function.  Otherwise put an error log up saying that the analysis has not started.  This check is required
#because OpenStudio_server 2.8.1 run the server finalization script at the start and end of the analysis rather than
#just at the end.
analysis_json = get_analysis_info(osa_id: analysis_id)
object_keys = get_analysis_objects(osa_id: analysis_id, bucket_name: bucket_name, analysis_json: analysis_json, lambda_region: aws_lambda_region, s3_region: aws_s3_region)
file_prefix = ['simulations']
if object_keys.empty?
  s3 = Aws::S3::Resource.new(region: aws_s3_region)
  bucket = s3.bucket(bucket_name)
  file_id = "error_coll_log_" + curr_time
  log_file_contents = "No analysis data could be found in folder with analysis ID: #{analysis_id}; and analysis name: #{analysis_json[:analysis_name]}."
  log_obj = bucket.object("log/" + file_id)
  log_obj.put(body: log_file_contents)
elsif proc_local.downcase != "alllocal"
  # If an s3 object with the analysis_id exists then first run the lambda function which extracts the qaqc.json file
  # form the result.zip files and combines them into simulations_#.json files in sets of 500.  Once successfully
  # completed them combine the simulations_#.json files into a final simulations.json file and put it on s3.  If
  # proc_local is true this is done on the EC2 instance, if it is false this is done via a lambda function.  The lambda
  # function will use less processing (and data transfer) on the EC2 instance which may reduce the likelyhood of data
  # transfer errors.  However, the lambda function is limited to 3GB of memory and can only run for up to 15 minutes.
  col_lambda_resp, cycles = invoke_lambda(osa_id: analysis_id, bucket_name: bucket_name, object_keys: object_keys, analysis_json: analysis_json, lambda_region: aws_lambda_region, s3_region: aws_s3_region)
  #Need to fix this so it actually checks for a response.
  if col_lambda_resp.empty? || col_lambda_resp[0].nil? || cycles.nil?
    "There was an error in the lambda function which compiles qaqc.json files into simulations files."
  else
    ammend_cycles = cycles.to_i + 1
    col_res_resp_all = []
    if proc_local.downcase == "false"
      # Currently this only appends simulations_# files but you could modify the compile_multizip_sub_BTAP_results lambda
      # funciton to append other files in the results.zip files and then compile those here too (as was originally done
      # with the eplus error files).
      file_prefix.each do |file_pref|
        puts file_pref
        col_res_resp = col_res(osa_id: analysis_id, bucket_name: bucket_name, cycles: ammend_cycles, file_pref: file_pref, analysis_json: analysis_json, lambda_region: aws_lambda_region, s3_region: aws_s3_region)
        col_res_resp_all << col_res_resp
      end
    elsif proc_local.downcase == "partlocal"
      file_prefix.each do |file_pref|
        puts file_pref
        col_res_resp = loc_col_res(osa_id: analysis_id, bucket_name: bucket_name, append_tag: file_pref, cycle_count: ammend_cycles, analysis_name: analysis_json[:analysis_name], region: aws_region)
        col_res_resp_all << col_res_resp
      end
    end
  end
elsif proc_local.downcase == "alllocal"
  search_file = 'qaqc.json'
  output = collate_output_locally(osa_id: analysis_id, bucket_name: bucket_name, append_tags: file_prefix, analysis_name: analysis_json[:analysis_name], region: aws_region, object_keys: object_keys, search_file: search_file)
  puts output
end
