#! env ruby

require 'optparse'
require 'ostruct'
require 'pathname'
require 'date'
require_relative 'wacb'

#
# ----------------------------------------------------------------------
# Command line handling.
# ----------------------------------------------------------------------
#

class CmdLine
  def self.parse(args)
    options = OpenStruct.new
    options.outputType = :Html
    options.outputDirectory = "."
    options.chatName = nil
    options.printChatNames = false
    options.printChatParticipants = nil
    options.title = nil
    options.me = nil
    options.from = nil
    options.to = nil
    options.senderMap = {}
    options.verbose = 0
    options.split = nil
    options.emojiDir = nil
    options.imageWidth = nil
    options.imageHeight = nil
    options.backgroundImage = nil
    options.attachments = nil
    options.renameAttachments = false

    opt_parser = OptionParser.new do |opts|
      opts.banner = "Usage: c2h.rb [options] inputFile ..."
      opts.on("--outputType=[html,chat]", "Output type (default is Html).") do |o|
        if o.downcase == "html"
          options.outputType = :Html
        elsif o.downcase == "chat"
          options.outputType = :Chat
        else
          raise "Invalid value for --outputType option: \"#{o}\""
        end
      end
      opts.on("-o", "--outputDirectory=DIR", "Output directory, will be created if it does not exist.") do |o|
        options.outputDirectory = o
      end
      opts.on("-n", "--chatName=name", "Chat name (only relevant for Explorer for WhatsApp files).") do |o|
        options.chatName = o
      end
      opts.on("--printChatNames", "No conversion, just print the names of all chats.") do
        options.printChatNames = true
      end
      opts.on("--printChatParticipants", "No conversion, just print the names of all participants.") do
        options.printChatParticipants = true
      end
      opts.on("--from=yyyy[-mm[-dd]]", "Select messages from this date or later.") do |date|
        parts = date.split("-")
        year = parts[0].to_i
        month = (parts.size() > 1) ? parts[1].to_i : 1
        day = (parts.size() > 2) ? parts[2].to_i : 1
        options.from = Date.new(year, month, day)
      end
      opts.on("--to=yyyy[-mm[-dd]]", "Select messages from until this date.") do |date|
        parts = date.split("-")
        year = parts[0].to_i
        month = (parts.size() > 1) ? parts[1].to_i : -1
        day = (parts.size() > 2) ? parts[2].to_i : -1
        options.to = Date.new(year, month, day)
      end
      opts.on("--me=name", "Identify yourself.") do |me|
        options.me = me
      end
      opts.on("--map=<sender=name>,...", Array, "Map sender ids to proper names.") do |list|
        list.each { |map|
          senderId, name = map.split("=")
          options.senderMap[senderId] = name
        }
      end
      opts.on("--attachments=[Copy,Move]", "Copy or move attachments to output directory.") do |o|
        if o.downcase == "copy"
          options.attachments = :Copy
        elsif o.downcase == "move"
          options.attachments = :Move
        else
          raise "Invalid value for --attachments option: \"#{o}\""
        end
      end
      opts.on("--renameAttachments", "Rename attachments by date.") do
        options.renameAttachments = true
      end
      opts.on("-t", "--title=Title", "[HTML] Chat title.") do |t|
        options.title = t
      end
      opts.on("--split=[month,year]", "[HTML] Split into monthly or annual files.") do |o|
        if o.downcase == "month"
          options.split = :Month
        elsif o.downcase == "year"
          options.split = :Year
        else
          raise "Invalid value for --split option: \"#{o}\""
        end
      end
      opts.on("--emojiDir=directory", "[HTML] Use emoji image files from this directory.") do |e|
        options.emojiDir = e
      end
      opts.on("-b", "--backgroundImage=fileName", "[HTML] Background image name.") do |b|
        options.backgroundImage = b
      end
      opts.on("--imageSize=<width>x<height>", "[HTML] Limit size of embedded images, default 320x240.") do |s|
        sa = s.split("x")
        options.imageWidth = sa[0].to_i
        options.imageHeight = sa[1].to_i
      end
      opts.on("-v", "--verbose", "Increase verbosity.") do
        options.verbose = options.verbose + 1
      end
      opts.on_tail("-h", "--help", "Show this message.") do
        puts opts
        exit
      end
    end

    opt_parser.parse!(args)
    return options, args
  end
end

options, inputFiles = CmdLine.parse(ARGV)

if inputFiles.empty?
  CmdLine.parse(["-h"]) # exits
end

#
# ----------------------------------------------------------------------
# Main.
# ----------------------------------------------------------------------
#

allMessages = WhatsAppChatBeautifier::Messages.new()
allMessages.setSenderMap(options.senderMap)
log = WhatsAppChatBeautifier::ConsoleOutput.new(options.verbose)

#
# Load input files.
#

inputFiles.each { |inputFileName|
  log.begin("Loading chat from \"#{inputFileName}\" ... ")
  inputFile = WhatsAppChatBeautifier.openInput(inputFileName)
  cp = WhatsAppChatBeautifier.parseChat(inputFile, options.me, options.from, options.to)
  log.end()

  #
  # Print chat names.
  #

  if options.printChatNames
    if !cp.is_a?(WhatsAppChatBeautifier::ExwaParser)
      raise "The --chatNames option is only available with Explorer for WhatsApp files."
    end
    puts("Chat names:")
    chatNames = cp.getChatNames()

    chatNames.each_key { |chatName|
      puts("\t" + chatName)
      if options.verbose > 0
        chatNames[chatName].each { |p|
          puts("\t\t" + p)
        }
      end
    }
    exit
  end

  #
  # Select the desired chat.
  #

  if cp.is_a?(WhatsAppChatBeautifier::ExwaParser)
    if !options.chatName
      raise "Must use --chatName with Explorer for WhatsApp files."
    end

    selectedChat = cp.matchChatName(options.chatName)
    raise "Oops, chat \"#{options.chatName}\" not found." if !selectedChat

    log.begin("Selecting chat \"#{selectedChat}\" ... ")
    cp.select(selectedChat)
    log.end()
  end

  #
  # When the "Me" option is not given, the WhatsApp parser selects on
  # of the chat participants as "me".
  #

  if !options.me and cp.is_a?(WhatsAppChatBeautifier::WhatsAppParser)
    options.me = cp.getMe()
  end

  messages = cp.getMessages()
  allMessages.add(messages, inputFile)

  #
  # Print chat participants.
  #

  if options.printChatParticipants
    puts("Chat participants:")
    participants = allMessages.getSenders()

    participants.each { |participant|
      puts("\t" + participant)
    }
    exit
  end
}

#
# Create output directory if it does not exist.
#

outputDir = Pathname.new(options.outputDirectory)

if !outputDir.directory? and !outputDir.exist?
  outputDir.mkdir()
end

if !outputDir.directory?
  puts "Oops: \"" + outputDir.to_s + "\" is not a directory."
  exit
end

#
# Export
#

case (options.outputType)
when :Html
  htmlExporterOptions = {
    :me => options.me,
    :title => options.title,
    :backgroundImage => options.backgroundImage,
    :split => options.split,
    :emojiDir => options.emojiDir,
    :imageWidth => options.imageWidth,
    :imageHeight => options.imageHeight,
    :attachments => options.attachments,
    :renameAttachments => options.renameAttachments,
    :log => log
  }

  wace = WhatsAppChatBeautifier::HtmlExporter.new(outputDir, allMessages, htmlExporterOptions)
  wace.export()

when :Chat
  whatsAppExporterOptions = {
    :me => options.me,
    :attachments => options.attachments,
    :renameAttachments => options.renameAttachments,
    :log => log
  }

  wace = WhatsAppChatBeautifier::WhatsAppExporter.new(outputDir, allMessages, whatsAppExporterOptions)
  wace.export()

else
  raise "Oops"
end
