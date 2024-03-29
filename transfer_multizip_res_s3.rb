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
# gem_loc = '/usr/local/lib/ruby/gems/2.2.0/gems/'
gem_loc = '/var/lib/gems/2.5.0/gems/'
gem_dirs = Dir.entries(gem_loc).select {|entry| File.directory? File.join(gem_loc,entry) and !(entry =='.' || entry == '..') }
gem_dirs.sort.each do |gem_dir|
  lib_loc = ''
  lib_loc = gem_loc + gem_dir + '/lib'
  $LOAD_PATH.unshift(lib_loc) unless $LOAD_PATH.include?(lib_loc)
end 

require 'bundler'
require 'securerandom'
require 'aws-sdk-s3'
require 'json'
require 'zip'
require 'rest-client'
require 'fileutils'

# Source copied and modified from https://github.com/rubyzip/rubyzip
# creates a zip of the given files and places the zipped file with the
# name 'out_file_name' (includes full path to file).
def zip_results(in_files:, out_file_name:)
  Zip::File.open(out_file_name, Zip::File::CREATE) do |zipfile|
    in_files.each do |in_file|
      # Two arguments:
      # - The name of the file as it will appear in the archive
      # - The original file, including the path to find it
      zipfile.add(in_file[:filename], File.join(in_file[:location], in_file[:filename]))
    end
  end
end

def get_analysis_name(aid:)
  analysis_json = JSON.parse(RestClient.get("http://web:80/analyses/#{aid}.json", headers={}))
  analysis_name = []
  unless analysis_json.nil?
    analysis_name=analysis_json['analysis']['display_name']
  end
  return analysis_name
end

def mod_qaqc_file(qaqc_loc:, analysis_name:, analysis_id:, datapoint_id:)
  qaqc_hash = JSON.parse(File.read(qaqc_loc))
  code_ver = qaqc_hash['measure_data_table'].select{|data|
    data['measure_name'].to_s.upcase == "btap_standard_loads".upcase
  }
  template = code_ver[0]['value']
  building_type = qaqc_hash['building']['name']
  qaqc_hash['analysis_id'] = analysis_id
  qaqc_hash['analysis_name'] = analysis_name
  qaqc_hash['run_uuid'] = datapoint_id
  qaqc_hash['building_type'] = building_type
  qaqc_hash['template'] = template
  File.open(qaqc_loc, 'w') { |file| file.write(JSON.generate(qaqc_hash)) }
end

#Get datapoint directory passed from worker finalization script.
input_arguments = ARGV
out_dir = input_arguments[0].to_s
bucket_name = input_arguments[1].to_s
analysis_id = input_arguments[2].to_s
datapoint_id = input_arguments[3].to_s
aws_region = input_arguments[4].to_s

#Set up s3.
s3 = Aws::S3::Resource.new(region: aws_region)
bucket = s3.bucket(bucket_name)

#Get analysis name
analysis_name = get_analysis_name(aid: analysis_id)

# Determine where the files are.
main_dir = File.expand_path("..", Dir.pwd)
out_file_loc = main_dir + "/" + out_dir + "/"

qaqc_full_loc = file_loc = Dir["#{out_file_loc}**/qaqc.json"]
if qaqc_full_loc.empty?
  qaqc_loc = ""
else
  mod_qaqc_file(qaqc_loc: qaqc_full_loc[0], analysis_name: analysis_name, analysis_id: analysis_id, datapoint_id: datapoint_id)
  qaqc_full_loc = File.dirname(qaqc_full_loc[0])
  qaqc_loc = qaqc_full_loc[out_file_loc.length.to_i..-1] + "/"
end
# Files to retrieve:
out_files = [
    {
        filename: "out.osw",
        location: ""
    },
    {
        filename: "oscli_simulation.log",
        location: ""
    },
    {
        filename: "in.osm",
        location: "run/"
    },
  	{
        filename: "in.idf",
        location: "run/"
    },
    {
        filename: "eplustbl.html",
        location: "reports/"
    },
    {
        filename: "qaqc.json",
        location: qaqc_loc
    },
    {
        filename: "run.log",
        location: "run/"
    },
    {
        filename: "eplusout.err",
        location: "run/"
    },
    {
        filename: "openstudio_results_report.html",
        location: "reports/"
    }
]
out_log = ""
zip_files = []
# Check if the files exist.  If they do not add them to the log of files which could not be found.
out_files.each do |out_file|
  if File.file?(File.join(out_file_loc, out_file[:location], out_file[:filename]))
    zip_files << {
        filename: out_file[:filename],
        location:  out_file_loc + out_file[:location]
    }
  else
    out_log += "Could not find #{out_file_loc + out_file[:location] + out_file[:filename]}\n"
  end
end
unless out_log == ""
  File.open(File.join(out_file_loc, "missing_files.log"), 'w') {|file| file.write(out_log)}
  zip_files << {
      filename: "missing_files.log",
      location: out_file_loc
  }
end
# Create the name of the results zip file.
zip_file_name = out_file_loc + "results.zip"

# Zip the files.
zip_results(in_files: zip_files, out_file_name: zip_file_name)

# Build S3 object name and put on S3
file_id = analysis_name + "_" + analysis_id + "/" + datapoint_id + ".zip"
out_obj = bucket.object(file_id)
while out_obj.exists? == false
  out_obj.upload_file(zip_file_name)
end
File.delete(zip_file_name) if File.exist?(zip_file_name)
if File.file?(File.join(out_file_loc, "missing_files.log"))
  File.delete(File.join(out_file_loc, "missing_files.log"))
end
