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


# Determine where the files are.
main_dir = File.expand_path("..", Dir.pwd)
out_file_loc = main_dir + "/" + out_dir + "/"

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
        filename: "eplustbl.html",
        location: "reports/"
    },
    {
        filename: "qaqc.json",
        location: "run/001_btap_results/"
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
        filename: "test.txt",
        location: ""
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
analysis_name = get_analysis_name(aid: analysis_id)
file_id = analysis_name + "_" + analysis_id + "/" + datapoint_id + ".zip"
out_obj = bucket.object(file_id)
while out_obj.exists? == false
  out_obj.upload_file(zip_file_name)
end
File.delete(zip_file_name) if File.exist?(zip_file_name)
