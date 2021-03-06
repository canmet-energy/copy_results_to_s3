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
require 'aws-sdk-iam'
require 'json'
require 'zip'

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

#Get datapoint directory passed from worker finalization script.
input_args = ARGV
out_dir = input_args[0].to_s
user_accnt = input_args[1].to_s
iam_policy = input_args[2].to_s

region = 'us-east-1'
bucket_name = 'btapresultsbucket'

sts = Aws::STS::Client.new(region: region)
creds = sts.get_federation_token({
    duration_seconds: 3600,
    name: user_accnt,
    policy:  "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"Stmt1\",\"Effect\":\"Allow\",\"Action\":\"#{iam_policy}\",\"Resource\":\"arn:aws:s3:::#{bucket_name}\"}]}",
                                 })

#Set up s3.

s3 = Aws::S3::Resource.new(region: region, credentials: creds)

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
