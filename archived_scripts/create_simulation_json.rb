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

gem_loc = '/usr/local/lib/ruby/gems/2.2.0/gems/'
gem_dirs = Dir.entries(gem_loc).select {|entry| File.directory? File.join(gem_loc,entry) and !(entry =='.' || entry == '..') }
gem_dirs.sort.each do |gem_dir|
  lib_loc = ''
  lib_loc = gem_loc + gem_dir + '/lib'
  $LOAD_PATH.unshift(lib_loc) unless $LOAD_PATH.include?(lib_loc)
end

require 'bundler'
require 'aws-sdk-s3'
require 'json'

analysis_id = ARGV[0].to_s

region = 'us-east-1'
s3 = Aws::S3::Resource.new(region: region)
bucket_name = 'btapresultsbucket'
bucket = s3.bucket(bucket_name)

time_obj = Time.new
curr_time = time_obj.year.to_s + "-" + time_obj.month.to_s + "-" + time_obj.day.to_s + "_" + time_obj.hour.to_s + ":" + time_obj.min.to_s + ":" + time_obj.sec.to_s + ":" + time_obj.usec.to_s

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
if error_col.empty?
  file_id = "error_coll_log_" + curr_time
  log_file_loc = "./" + file_id + ".txt"
  log_file = File.open(log_file_loc, 'w')
  log_file.puts "#{error_temp_col} could not be found."
  log_file.close
  log_obj = bucket.object("log/" + file_id)
  log_obj.upload_file(log_file_loc)
else
  File.open(error_temp_col,"w") {|each_file| each_file.write(JSON.pretty_generate(error_col))}
  error_out_id = analysis_id + "/" + "error_col.json"
  error_out_obj = bucket.object(error_out_id)
  while error_out_obj.exists? == false
    error_out_obj.upload_file(error_temp_col)
  end
  #Delete the collated error.json file.
  File.delete(error_temp_col)
end

#Generated a collated qaqc.json file using the collated array of datapoint qaqc hashes.
#Create an s3 object and push the collated qaqc.json file to it (this makes the simulations.json for the analysis).
if qaqc_col.empty?
  file_id = "qaqc_coll_log_" + curr_time
  log_file_loc = "./" + file_id + ".txt"
  log_file = File.open(log_file_loc, 'w')
  log_file.puts "#{qaqc_temp_col} could not be found."
  log_file.close
  log_obj = bucket.object("log/" + file_id)
  log_obj.upload_file(log_file_loc)
else
  File.open(qaqc_temp_col,"w") {|each_file| each_file.write(JSON.pretty_generate(qaqc_col))}
  qaqc_out_id = analysis_id + "/" + "simulations.json"
  qaqc_out_obj = bucket.object(qaqc_out_id)
  while qaqc_out_obj.exists? == false
    qaqc_out_obj.upload_file(qaqc_temp_col)
  end
  #Delete the collated qaqc.json file.
  File.delete(qaqc_temp_col)
end