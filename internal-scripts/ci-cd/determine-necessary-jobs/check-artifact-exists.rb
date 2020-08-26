#!/usr/bin/env ruby

NAME = ENV['NAME'] || abort("Required environment variable: NAME")

artifacts = File.open('artifacts.txt', 'r:utf-8') do |f|
  f.read.split("\n")
end

if artifacts.include?(NAME)
  puts "::set-output name=exists::true"
  puts "::set-output name=absent::false"
  puts "Artifact #{NAME} exists"
else
  puts "::set-output name=exists::false"
  puts "::set-output name=absent::true"
  puts "Artifact #{NAME} does not exist"
end
