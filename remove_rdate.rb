require 'stringio'
require 'net/http'
require 'icalendar'

def remove_rdate file
    #cal_file_disk = File.open(file, "r")
    cal_file_string = ""
    cal_file = nil
    file.each_line do |line|
        if (line[0, 5] != "RDATE")
            stringLine = line.encode('UTF-8', :invalid => :replace, :undef => :replace)
            # seek back to the beginning of the line.
            cal_file_string += stringLine
        end
    end
    return cal_file = StringIO.new(cal_file_string)
end