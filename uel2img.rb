#! /bin/ruby

#
# Extract images from the Unicode emoji list and store in a local directory.
#

require 'optparse'
require 'ostruct'
require 'pathname'
require 'uri'
require 'base64'

class CmdLine
  def self.parse(args)
    options = OpenStruct.new
    options.input = "http://www.unicode.org/emoji/charts/emoji-list.html"
    options.outputDirectory = ""

    opt_parser = OptionParser.new do |opts|
      opts.banner = "Usage: uel2img.rb [options]"
      opts.on("-i", "--input=URL/File", "Read input from file or URL.") do |i|
        options.input = i
      end
      opts.on("-o", "--outputDirectory=DIR", "Output directory, will be created or cleaned.") do |o|
        options.outputDirectory = o
      end
      opts.on_tail("-h", "--help", "Show this message.") do
        puts opts
        exit
      end
    end

    opt_parser.parse!(args)
    options
  end
end

$options = CmdLine.parse(ARGV)

if $options.input.empty? or $options.outputDirectory.empty?
  CmdLine.parse(["-h"]) # exits
end

#
# Read input from local file or remote server.
#

uri = URI($options.input)

if uri.scheme
  require 'net/http'
  inputData = Net::HTTP.get(uri)
else
  inputFileName = Pathname.new($options.input)
  inputFile = File.open(inputFileName, "rb")
  inputData = inputFile.read
  inputFile.close
end

$outputDir = Pathname.new($options.outputDirectory)

#
# Create output directory if it does not exist.
#

if !$outputDir.directory? and !$outputDir.exist?
  $outputDir.mkdir()
end

if !$outputDir.directory?
  puts "Oops: \"" + $outputDir.to_s + "\" is not a directory."
  exit
end

#
# Parse image data.
#

inputData.each_line { |line|
  md1 = line.match("<a href=.[a-z.-]+#([0-9A-Fa-f_]+)")
  md2 = line.match("src=.data:image/png;base64,([A-Za-z0-9/+]+)")

  if md1 and md2
    codePoint = md1[1].downcase
    imageData = Base64.decode64(md2[1])
    imageFileName = $outputDir.join("emoji_u#{codePoint}.png")
    imageFile = File.open(imageFileName, "wb")
    imageFile.write(imageData)
    imageFile.close
  end
}
