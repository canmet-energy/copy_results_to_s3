#!/usr/bin/env ruby

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

region = 'us-east-1'
s3 = Aws::S3::Resource.new(region: region)
bucket_name = 'btapresultsbucket'
bucket = s3.bucket(bucket_name)

time_obj = Time.new
curr_time = time_obj.year.to_s + "-" + time_obj.month.to_s + "-" + time_obj.day.to_s + "_" + time_obj.hour.to_s + ":" + time_obj.min.to_s + ":" + time_obj.sec.to_s + ":" + time_obj.usec.to_s
curr_dir = Dir.pwd
main_dir = curr_dir[0..-4]
res_dirs = Dir.entries(main_dir).select {|entry| File.directory? File.join(main_dir,entry) and !(entry =='.' || entry == '..') }
out_dir = res_dirs.select { |res_dir| res_dir.match(/data_point_/) }.first
out_file_loc = main_dir + out_dir + "/"
out_file = out_file_loc + "out.osw"
osa_id = ""
osd_id = ""
file_id = ""
if File.file?(out_file)
  File.open(out_file, "r") do |f|
    f.each_line do |line|
      if line.match(/   \"osa_id\" : \"/)
	    osa_id = line[15..-4]
	  elsif line.match(/   \"osd_id\" : \"/)
	    osd_id = line[15..-4] 
	  end
    end
	if osa_id == "" || osd_id == ""
      file_id = "log_" + curr_time
	  log_file_loc = "./" + file_id + "txt"
	  log_file = File.open(log_file_loc, 'w')
	  log_file.puts "Either could not find osa_id or osd_id in out.osw file."
	  log_file.close
	  log_obj = bucket.object("log/" + file_id)
	  log_obj.upload_file(log_file_loc)
    else
      file_id = osa_id + "/" + osd_id + ".osw"
	  out_obj = bucket.object(file_id)
	  resp = []
	  while resp == []
	    out_obj.upload_file(out_file)
	    resp = bucket.objects.select { |resp_each| resp_each.key == file_id }
	  end
    end
  end
else
  file_id = "log_" + curr_time
  log_file_loc = "./" + file_id + "txt"
  log_file = File.open(log_file_loc, 'w')
  log_file.puts "#{out_file} could not be found."
  log_file.close
  log_obj = bucket.object("log/" + file_id)
  Log_obj.upload_file(log_file_loc)
end
