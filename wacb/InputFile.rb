module WhatsAppChatBeautifier
  #
  # ----------------------------------------------------------------------
  # Manage input file and input directory.
  # ----------------------------------------------------------------------
  #

  class DirInput
    def initialize(dirName = nil, fileName = nil)
      if dirName
        openFile(dirName, fileName)
      end
    end

    def openFile(dirName, fileName)
      @inputDir = Pathname.new(dirName)
      if fileName
        files = [ fileName ]
      else
        files = Dir.entries(@inputDir).select { |fileName|
          extName = Pathname.new(fileName).extname().downcase()
          extName == ".xlsx" or extName == ".txt"
        }
      end
      if files.size == 0
        raise "No .txt or .xlsx files in directory \"#{dirName.to_s}\""
      elsif files.size > 1
        raise "More than one .txt or .xlsx files in directory \"#{dirName.to_s}\""
      end

      @inputFile = @inputDir.join(files[0])
      @fileType = (@inputFile.extname().downcase() == ".xlsx") ? :Xlsx : :Text
    end

    def type()
      return @fileType
    end

    def read()
      data = IO.binread(@inputFile)
      if @fileType == :Text
        data = data.force_encoding("UTF-8")
      end
      return data
    end

    def close()
    end

    def openAttachment(attachmentFileName)
      attachmentPath = @inputDir.join(attachmentFileName)
      inputStream = File.open(attachmentPath)
      return inputStream
    end

    def copyAttachment(attachmentFileName, outputFileName)
      attachmentPath = @inputDir.join(attachmentFileName)
      FileUtils.copy_file(attachmentPath, outputFileName)
    end

    def moveAttachment(attachmentFileName, outputFileName)
      attachmentPath = @inputDir.join(attachmentFileName)
      FileUtils.move(attachmentPath, outputFileName)
    end
  end

  class ZipInput
    def initialize(input = nil)
      require 'zip'
      if input
        openFile(input)
      end
    end

    def openFile(input)
      inputPath = Pathname.new(input)
      @zipFile = Zip::File.open(inputPath)
      xlsxFiles = @zipFile.glob('**/*.xlsx')
      textFiles = @zipFile.glob('**/*.txt')
      if xlsxFiles.size == 0 and textFiles.size == 0
        raise "No .txt or .xlsx files in zip \"#{inputPath.to_s}\""
      elsif xlsxFiles.size + textFiles.size > 1
        raise "More than one .txt and .xlsx files in zip \"#{inputPath.to_s}\""
      elsif xlsxFiles.size == 1
        @inputFile = xlsxFiles[0]
        @fileType = :Xlsx
      elsif textFiles.size == 1
        @inputFile = textFiles[0]
        @fileType = :Text
      else
        raise "Oops"
      end
      @inputDir = Pathname.new(@inputFile.name).dirname
    end

    def type()
      return @fileType
    end

    def read()
      data = @inputFile.get_input_stream().read()
      if @fileType == :Text
        data = data.force_encoding("UTF-8")
      end
      return data
    end

    def close()
      @zipFile.close()
    end

    def openAttachment(attachmentFileName)
      attachmentPath = @inputDir.join(attachmentFileName)
      inputStream = @zipFile.find_entry(attachmentPath).get_input_stream()
      return inputStream
    end

    def copyAttachment(attachmentFileName, outputFileName)
      attachmentPath = @inputDir.join(attachmentFileName)
      @zipFile.extract(attachmentPath, outputFileName)
    end

    def moveAttachment(attachmentFileName, outputFileName)
      raise "Can not move out of a zip file."
    end
  end

  def WhatsAppChatBeautifier.openInput(input)
    inputPath = Pathname.new(input)
    if inputPath.extname().downcase() == ".zip"
      return ZipInput.new(inputPath)
    elsif inputPath.directory?()
      return DirInput.new(inputPath)
    elsif inputPath.file?()
      return DirInput.new(inputPath.dirname, inputPath.basename)
    else
      raise "Unknown input \"#{input}\""
    end
  end
end
