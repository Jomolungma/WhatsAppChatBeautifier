module WhatsAppChatBeautifier
  #
  # ----------------------------------------------------------------------
  # Front-end function to determine type of chat and to instantiate the
  # right parser instance.
  # ----------------------------------------------------------------------
  #

  def WhatsAppChatBeautifier.parseChat(inputFile, me = nil, from = nil, to = nil)
    data = inputFile.read()

    if inputFile.type() == :Text
      magic = data[0..3]

      if magic == "<<< " or magic == ">>> "
        parser = ThreemaParser.new()
      else
        parser = WhatsAppParser.new(me)
      end
    elsif inputFile.type == :Xlsx
      parser = ExwaParser.new()
    else
      raise "Invalid input."
    end

    parser.load(data, from, to)
    return parser
  end
end
