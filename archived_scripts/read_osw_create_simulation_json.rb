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
require 'securerandom'
require 'aws-sdk-s3'
require 'json'

require 'rest-client'
require 'fileutils'
require 'zip'
require 'parallel'
require 'optparse'
require 'json'
require 'base64'
require 'colored'
require 'csv'

# Extract data from the osw file and write it on the disk. This method also calls process_simulation_json method
# which appends the qaqc data to the simulations.json. it only happens if the measure `btap_results` exist with
# `btap_results_json_zip` variable stored as part of the measure

# @param osw_json [:hash] osw file in json hash format
# @param output_folder [:string] parent folder where the data from osw will be extracted to
# @param uuid [:string] UUID of the datapoint
# @param simulations_json_folder [:string] root folder of the simulations.json file
# # @param aid [:string] analysis ID
def extract_data_from_osw(osw_json:, uuid:, aid:)
  results = osw_json
  out_json = []
  error_return = []
  output_folder = './'
  #itterate through all the steps of the osw file
  results['steps'].each do |measure|
    #puts "measure.name: #{measure['name']}"
    meausre_results_folder_map = {
        'openstudio_results':[
            {
                'measure_result_var_name': "eplustbl_htm",
                'filename': "#{output_folder}/eplus_table/#{uuid}-eplustbl.htm"
            },
            {
                'measure_result_var_name': "report_html",
                'filename': "#{output_folder}/os_report/#{uuid}-os-report.html"
            }
        ],
        'btap_view_model':[
            {
                'measure_result_var_name': "view_model_html_zip",
                'filename': "#{output_folder}/3d_model/#{uuid}_3d.html"
            }
        ],
        'btap_results':[
            {
                'measure_result_var_name': "model_osm_zip",
                'filename': "#{output_folder}/osm_files/#{uuid}.osm"
            },
            {
                'measure_result_var_name': "btap_results_hourly_data_8760",
                'filename': "#{output_folder}/8760_files/#{uuid}-8760_hourly_data.csv"
            },
            {
                'measure_result_var_name': "btap_results_hourly_custom_8760",
                'filename': "#{output_folder}/8760_files/#{uuid}-8760_hour_custom.csv"
            },
            {
                'measure_result_var_name': "btap_results_monthly_7_day_24_hour_averages",
                'filename': "#{output_folder}/8760_files/#{uuid}-mnth_24_hr_avg.csv"
            },
            {
                'measure_result_var_name': "btap_results_monthly_24_hour_weekend_weekday_averages",
                'filename': "#{output_folder}/8760_files/#{uuid}-mnth_weekend_weekday.csv"
            },
            {
                'measure_result_var_name': "btap_results_enduse_total_24_hour_weekend_weekday_averages",
                'filename': "#{output_folder}/8760_files/#{uuid}-endusetotal.csv"
            }
        ]
    }

    # if the measure is btapresults, then extract the osw file and qaqc json
    # While processing the qaqc json file, add it to the simulations.json file
    if measure["name"] == "btap_results" && measure.include?("result")
      measure["result"]["step_values"].each do |values|
        # extract the qaqc json blob data from the osw file and save it
        # in the output folder
        next unless values["name"] == 'btap_results_json_zip'
        btap_results_json_zip_64 = values['value']
        json_string =  Zlib::Inflate.inflate(Base64.strict_decode64( btap_results_json_zip_64 ))
        json = JSON.parse(json_string)
        # indicate if the current model is a baseline run or not
        # json['is_baseline'] = "#{flags[:baseline]}"

        #add ECM data to the json file
        measure_data = []
        results['steps'].each_with_index do |measure, index|
          step = {}
          measure_data << step
          step['name'] = measure['name']
          step['arguments'] = measure['arguments']
          if measure.has_key?('result')
            step['display_name'] = measure['result']['measure_display_name']
            step['measure_class_name'] = measure['result']['measure_class_name']
          end
          step['index'] = index
          # measure is an ecm if it starts with ecm_ (case ignored)
          step['is_ecm'] = !(measure['name'] =~ /^ecm_/i).nil? # returns true if measure name starts with 'ecm_' (case ignored)
        end

        json['measures'] = measure_data

        # add analysis_id and analysis name to the json file
        analysis_json = JSON.parse(RestClient.get("http://web:80/analyses/#{aid}.json", headers={}))
        json['analysis_id']=analysis_json['analysis']['_id']
        json['analysis_name']=analysis_json['analysis']['display_name']
        ret_json, curr_error_return = process_simulation_json(json: json, uuid: uuid, aid: aid, osw_file: results)
        out_json << ret_json
        error_return << curr_error_return
        puts "#{uuid}.json ok"
      end
    end # if measure["name"] == "btapresults" && measure.include?("result")
  end # of grab step files
  return out_json, error_return
end

# This method will append qaqc data to simulations.json
#
# @param json [:hash] contains original qaqc json file of a datapoint
# @param simulations_json_folder [:string] root folder of the simulations.json file
# @param osw_file [:hash] contains the datapoint's osw file
def process_simulation_json(json:, uuid:, aid:, osw_file:)
  #modify the qaqc json file to remove eplusout.err information,
  # and add separate building information and uuid key
  #json contains original qaqc json file on start

  error_return = ""
  building_type = ""
  epw_file = ""
  template = ""

  # get building_type, epw_file, and template from btap_create_necb_prototype_building inputs
  # if possible
  osw_file['steps'].each do |measure|
    next unless measure["name"] == "btap_create_necb_prototype_building"
    building_type = measure['arguments']["building_type"]
    epw_file =      measure['arguments']["epw_file"]
    template =      measure['arguments']["template"]
  end

  if json.has_key?('eplusout_err')
    json_eplus_warn = json['eplusout_err']['warnings'] unless json['eplusout_err']['warnings'].nil?
    json_eplus_fatal = json['eplusout_err']['fatal'].join("\n") unless json['eplusout_err']['fatal'].nil?
    json_eplus_severe = json['eplusout_err']['severe'].join("\n") unless json['eplusout_err']['severe'].nil?

    json['eplusout_err']['warnings'] = json['eplusout_err']['warnings'].size
    json['eplusout_err']['severe'] = json['eplusout_err']['severe'].size
    json['eplusout_err']['fatal'] = json['eplusout_err']['fatal'].size
  else
    error_return = error_return + "ERROR: Unable to find eplusout_err #{uuid}.json\n"
  end
  json['run_uuid'] = uuid
  #puts "json['run_uuid'] #{json['run_uuid']}"
  bldg = json['building']['name'].split('-')
  json['building_type'] = (building_type == "" ? (bldg[1]) : (building_type)  )
  json['template'] = (template == "" ? (bldg[0]) : (template)  )

  # output the errors to the error_log
  begin
    # write building_type, template, epw_file, QAQC errors, and sanity check
    # fails to the comma delimited file
    bldg_type = json['building_type']
    city = (epw_file == "" ? (json['geography']['city']) : (epw_file)  )
    json_error = ''
    json_error = json['errors'].join("\n") unless json['errors'].nil?
    json_sanity = ''
    json_sanity = json['sanity_check']['fail'].join("\n") unless json['sanity_check'].nil?

    # Ignore some of the warnings that matches the regex. This feature is implemented
    # to reduce the clutter in the error log. Additionally, if the number of
    # lines exceed a limit, excel puts the cell contents in the next row
    regex_patern_match = ['Blank Schedule Type Limits Name input -- will not be validated',
                          'You may need to shorten the names']
    matches = Regexp.new(Regexp.union(regex_patern_match),Regexp::IGNORECASE)
    json_eplus_warn = json_eplus_warn.delete_if {|line|
      !!(line =~ matches)
    }
    json_eplus_warn = json_eplus_warn.join("\n") unless json_eplus_warn.nil?
    error_return = {
        bldg_type: bldg_type,
        template: template,
        city: city,
        json_error: json_error,
        json_sanity: json_sanity,
        json_eplus_warn: json_eplus_warn,
        json_eplus_fatal: json_eplus_fatal,
        json_eplus_sever: json_eplus_severe,
        analysis_id: json['analysis_id'],
        analysis_name: json['analysis_name'],
        run_uuid: uuid
    }
  rescue => exception
    puts "[Ignore] There was an error writing to the BTAP Error Log"
    puts exception
  end
  return json, error_return
end

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

# Source copied and modified from https://github.com/rubyzip/rubyzip.
# This extracts the data from a zip file that presumably contains a json file.  It returns the contents of that file in
# an array of hashes (if there were multiple files in the zip file.)
def unzip_osw(zip_file:)
  osw_json = []
  Zip::File.open(zip_file) do |file|
    file.each do |entry|
      puts "Extracting #{entry.name}"
      osw_json << JSON.parse(entry.get_input_stream.read)
    end
  end
  return osw_json
end

analysis_id = ARGV[0].to_s

region = 'us-east-1'
s3 = Aws::S3::Resource.new(region: region)
bucket_name = 'btapresultsbucket'
bucket = s3.bucket(bucket_name)

time_obj = Time.new
curr_time = time_obj.year.to_s + "-" + time_obj.month.to_s + "-" + time_obj.day.to_s + "_" + time_obj.hour.to_s + ":" + time_obj.min.to_s + ":" + time_obj.sec.to_s + ":" + time_obj.usec.to_s

osw_temp_file = './osw_temp.json'
qaqc_temp_col = './simulation.json'
error_temp_col = './error_col.json'
qaqc_zip = './qaqc'
error_zip = './error'
error_col = []
qaqc_col = []

#Go through all of the objects in the s3 bucket searching for the qaqc.json and error.json objects related the current
#analysis.
bucket.objects.each do |bucket_info|
  unless (/#{analysis_id}/ =~ bucket_info.key.to_s).nil?
    #Remove the / characters with _ to avoid regex problems
    replacekey = bucket_info.key.to_s.gsub(/\//, '_')
    #Search for objects with the current analysis id that have .zip in them, then extract the qaqc and error data
    #and collate those into a qaqc_col array of hashes and an error col array of hashes.  Ultimately thes end up in an
    #s3 bucket on aws.
    unless (/.zip/ =~ replacekey.to_s).nil?
      #If you find an osw.zip file try downloading it and adding the information to the error_col array of hashes.
      osw_index = 0
      while osw_index < 10
        osw_index += 1
        bucket_info.download_file(osw_temp_file)
        osw_index = 11 if File.exist?(osw_temp_file)
      end
      if File.exist?(osw_temp_file)
        osw_json = unzip_osw(zip_file: osw_temp_file)
        osw_json.each do |osw|
          aid = osw['osa_id']
          uuid = osw['osd_id']
          if aid.nil? || uuid.nil?
            puts "Error either aid: #{aid} or uuid: #{uuid} not present"
          else
            qaqc, error_info = extract_data_from_osw(osw_json: osw, uuid: uuid, aid: aid)
            qaqc.each do |qaqc_ind|
              qaqc_col << qaqc_ind
            end
            error_info.each do |error_ind|
              error_col << error_ind
            end
          end
        end
        # Get rid of the datapoint osw file that was just downloaded.
        File.delete(osw_temp_file)
      else
        puts "Could not download #{bucket_info.key}"
      end
    end
  end
end

#Put the collated array of datapoint error hashes into a error_col.json file on s3.
if error_col.empty?
  file_id = "error_coll_log_" + curr_time
  log_file_loc = "./" + file_id + ".txt"
  log_file = File.open(log_file_loc, 'w')
  log_file.puts "No error data could be found."
  log_file.close
  log_obj = bucket.object("log/" + file_id)
  log_obj.upload_file(log_file_loc)
else
  File.open(error_temp_col,"w") {|each_file| each_file.write(JSON.pretty_generate(error_col))}
  error_zip_file = zip_results(in_file: error_temp_col, out_file_name: error_zip)
  error_out_id = analysis_id + "/" + "error_col.zip"
  error_out_obj = bucket.object(error_out_id)
  while error_out_obj.exists? == false
    error_out_obj.upload_file(error_zip_file)
  end
  File.delete(error_temp_col) if File.exist?(error_temp_col)
  File.delete(error_zip_file) if File.exist?(error_zip_file)
end

#Put the collated array of datapoint qaqc hashes into a simulation.json file on s3.
if qaqc_col.empty?
  file_id = "qaqc_coll_log_" + curr_time
  log_file_loc = "./" + file_id + ".txt"
  log_file = File.open(log_file_loc, 'w')
  log_file.puts "No qaqc data could be found."
  log_file.close
  log_obj = bucket.object("log/" + file_id)
  log_obj.upload_file(log_file_loc)
else
  File.open(qaqc_temp_col,"w") {|each_file| each_file.write(JSON.pretty_generate(qaqc_col))}
  qaqc_zip_file = zip_results(in_file: qaqc_temp_col, out_file_name: qaqc_zip)
  qaqc_out_id = analysis_id + "/" + "simulations.zip"
  qaqc_out_obj = bucket.object(qaqc_out_id)
  while qaqc_out_obj.exists? == false
    qaqc_out_obj.upload_file(qaqc_zip_file)
  end
  File.delete(qaqc_temp_col) if File.exist?(qaqc_temp_col)
  File.delete(qaqc_zip_file) if File.exist?(qaqc_zip_file)
end