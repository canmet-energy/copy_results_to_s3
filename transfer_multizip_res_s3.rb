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

def get_analysis_name(aid:)
  analysis_json = JSON.parse(RestClient.get("http://web:80/analyses/#{aid}.json", headers={}))
  analysis_name = []
  unless analysis_json.nil?
    analysis_name=analysis_json['analysis']['display_name']
  end
  return analysis_name
end

#Get datapoint directory passed from worker finalization script.
input_arguments = ARGV
out_dir = input_arguments[0].to_s
bucket_name = input_arguments[1].to_s
analysis_id = input_arguments[2].to_s
datapoint_id = input_arguments[3].to_s

#Set up s3.
region = 'us-east-1'
s3 = Aws::S3::Resource.new(region: region)
bucket = s3.bucket(bucket_name)

#Get current time and date (to use in logs)
time_obj = Time.new
curr_time = time_obj.year.to_s + "-" + time_obj.month.to_s + "-" + time_obj.day.to_s + "_" + time_obj.hour.to_s + ":" + time_obj.min.to_s + ":" + time_obj.sec.to_s + ":" + time_obj.usec.to_s

#Determine where osw file is
# curr_dir = Dir.pwd
# main_dir = curr_dir[0..-4]
main_dir = File.expand_path("..", Dir.pwd)
out_file_loc = main_dir + "/" + out_dir + "/"

# Files to retrieve:
osw_file = out_file_loc + "out.osw"
datapoint_log = out_file_loc + "oscli_simulation.log"
osm_file = out_file_loc + "run/in.osm"
ephtml_file = out_file_loc + "reports/eplustbl.html"
qaqc_file = out_file_loc + "run/001_btap_results/qaqc.json"
run_log = out_file_loc + "run/run.log"
eperr_log = out_file_loc + "run/eplusout.err"

out_log = []
zip_files = []
if File.file?(osw_file)
  zip_files << osw_file
else
  out_log = out_log + "Could not find #{osw_file}\n"
end
if File.file?(datapoint_log)
  zip_files << datapoint_log
else
  out_log = out_log + "Could not find #{datapoint_log}\n"
end
if File.file?(osm_file)
  zip_files << osm_file
else
  out_log = out_log + "Could not find #{osm_file}\n"
end
if File.file?(ephtml_file)
  zip_files << ephtml_file
else
  out_log = out_log + "Could not find #{ephtml_file}\n"
end
if File.file?(qaqc_file)
  zip_files << qaqc_file
else
  out_log = out_log + "Could not find #{qaqc_file}\n"
end
if File.file?(run_log)
  zip_files << run_log
else
  out_log = out_log + "Could not find #{run_log}\n"
end
if File.file?(eperr_log)
  zip_files << eperr_log
else
  out_log = out_log + "Colud not find #{eperr_log}\n"
end


#Initialize some file locations
osa_id = ""
osd_id = ""
file_id = ""

#Determine if osw is there, if not then put an error on s3.
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
      analysis_name = get_analysis_name(aid: osa_id)
      file_id = analysis_name + "_" + osa_id + "/" + osd_id + ".zip"
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
