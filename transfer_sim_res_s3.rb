#!/usr/bin/env ruby

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

res_path = "/mnt/openstudio/server/assets/"
res_file = "results." + analysis_id + ".zip"
res_file_path = res_path + res_file

time_obj = Time.new
curr_time = time_obj.year.to_s + "-" + time_obj.month.to_s + "-" + time_obj.day.to_s + "_" + time_obj.hour.to_s + ":" + time_obj.min.to_s + ":" + time_obj.sec.to_s + ":" + time_obj.usec.to_s

if File.file?(res_file_path)
  file_id = analysis_id + "/" + "results.zip"
  out_obj = bucket.object(file_id)
  resp = []
  while out_obj.exists? == false
    out_obj.upload_file(res_file_path)
  end
else
  file_id = "log_" + curr_time
  log_file_loc = "./" + file_id + ".txt"
  log_file = File.open(log_file_loc, 'w')
  log_file.puts "#{res_file_path} could not be found."
  log_file.close
  log_obj = bucket.object("log/" + file_id)
  log_obj.upload_file(log_file_loc)
end
