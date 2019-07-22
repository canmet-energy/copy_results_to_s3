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

# Source copied and modified from https://github.com/rubyzip/rubyzip
# creates a zip of the given file and places the zipped file at the
# same location as the file
def zip_single_file(file)
  return false unless File.exist?(file)
  folder = File.dirname(file)
  input_filename = File.basename(file)
  zipfile_name = "#{folder}/#{input_filename}.zip"
  puts "\n\tzipfile_name: #{zipfile_name}"
  ::Zip::File.open(zipfile_name, ::Zip::File::CREATE) do |zipfile|
    zipfile.get_output_stream(input_filename) do |out_file|
      out_file.write(File.open(file, 'rb').read)
    end
  end
end

def zip_res(in_dir:, in_file:)
  # Gather the required files
  Zip.warn_invalid_date = false

  # Zip Results
  directory_to_zip = in_dir
  output_file      = in_dir + 'output_osw.zip'
  puts "Zipping Files...".cyan
  zf = ZipFileGenerator.new(directory_to_zip, output_file)
  zf.write()

  puts "Zipping single files...".cyan

  zip_single_file(in_file)
  # list of files to create a local zipped copy
  files_to_zip = ["/mnt/openstudio/server/assets/results/#{uuid}/failed_run_error_log.csv",
                  "/mnt/openstudio/server/assets/results/#{uuid}/simulations.json"
  ]
  files_to_zip.each {|file|
    puts "Zipping #{file}"
    zip_single_file(file)
  }
  return out_zip
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
      zip_file_loc = zip_res(in_dir: out_file_loc, in_file: out_file)
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
