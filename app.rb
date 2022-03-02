#!/usr/bin/env ruby

require 'rubygems'
require 'bundler/setup'
require 'discordrb'

require 'tzinfo/data'
require 'rufus-scheduler'
require 'date'
require 'active_support/time'
require 'net/http'
require './db_init'

module Perms
  ADMINISTRATOR = "administrator"
  MODERATOR = "manage_channels"
  NORMALUSER = "send_messages"
end

@bot = Discordrb::Commands::CommandBot.new token: ENV['BOT_TOKEN'], prefix: 's.'
@scheduler = Rufus::Scheduler.new
@tz = TZInfo::Timezone.get(ENV['TZ'])

puts "This bot's invite URL is #{@bot.invite_url}."
puts 'Click on it to invite it to your server.'

ActiveGraph::Base.driver = Neo4j::Driver::GraphDatabase.driver(ENV['NEO4J_URL'], Neo4j::Driver::AuthTokens.basic('neo4j','Huong@897049'), encryption: false)

#Embed creation
def ping_student_for_class(student, class_time, class_name, class_location, channel)
    ping_message = ""
    student.each do |indiv_student|
      ping_message += "<@#{indiv_student.user_id}> "
    end
    channel.send_embed(ping_message) do |embed|
      embed.title = "#{class_name} - #{class_time}"
      embed.description = "Starting in 30 minutes @ #{class_location}"
      embed.timestamp = Time.now
    end
end

#User Delete function to be called by the command
def delete_user(user)
    user_node = UserNode.find_by(user_id: id)

    if (user_node.nil?)
      return "No user found"
    end
  
    user_node.destroy
    return "Delete successful"
end

#Function to view dates, as well as scheduling pings if required
def send_timetable(time_argument, schedule_ping, one_student, channel)
    today = time_argument.class == String ? Time.parse(time_argument) : time_argument
    today_string = today.strftime("%F")
    date_node = DateNode.find_by(date_today: today_string)
    channel_obj = channel.class == Integer ? @bot.channel(channel) : channel
    if (date_node.nil?)
      @bot.send_message(channel_obj, "No classes today yay!")
      return nil
    end
    students = date_node.user_nodes
    classes = date_node.class_nodes
    if (classes.empty? || students.empty?)
      @bot.send_message(channel_obj, "No classes today yay!")
      return nil
    end
    student_timetable = Hash.new()
    students.each do |student|
      student_timetable[student.user_id] = ""
    end
    classes.each do |class_node|
      class_time = class_node.class_time
      class_hour = class_time[0,2]
      class_minute = class_time[3,2]
      class_time_parsed = Time.new(today.year, today.month, today.day, class_hour, class_minute, 0, @tz)
      class_name = class_node.class_name
      class_location = class_node.class_location
      local_student = class_node.user_nodes
      next if local_student.empty?
      local_student.each do |student|
        student_timetable[student.user_id] += "#{class_time} - #{class_name} @ #{class_location}\n"
      end
      if (schedule_ping)
        @scheduler.at class_time_parsed - 1800 do
          ping_student_for_class(local_student, class_time, class_name, class_location, channel_obj)
        end
      end
    end
    if (one_student == nil)
      students.each do |student|
        desc = student_timetable[student.user_id].split("\n").sort().join("\n")
        student_discord = @bot.user(student.user_id.to_i)
        channel_obj.send_embed("<@#{student.user_id}>") do |embed|
          embed.title = "#{student_discord.username}'s timetable for #{today_string}"
          embed.description = desc
          embed.timestamp = Time.now
        end
      end
      return nil
    else
      desc = student_timetable[one_student.to_s] == nil ? "No classes for today yay!" : student_timetable[one_student.to_s].split("\n").sort().join("\n")
      student_discord = @bot.user(one_student)
      channel_obj.send_embed("<@#{one_student.to_s}>") do |embed|
        embed.title = "#{student_discord.username}'s timetable for #{today_string}"
        embed.description = desc
        embed.timestamp = Time.now
      end
      return nil
    end
end

#Date View command
@bot.command(:timetable, description: "Displays the timetable for a day", usage: "timetable [YYYY-MM-DD](optional, if skipped, will show today's timetable) [User](optional, if skipped, will show own's timetable, must follow the date)", max_args: 2) do |event, that_day, another_person|
    person = nil
    if another_person
      person = another_person.delete('<>@!').to_i
    else
      person = event.author.id
    end
    if that_day 
      begin
        send_timetable(that_day, false, person, event.channel)
      rescue
        next "Invalid date format. Please use YYYY-MM-DD"
      end
    else
      today = Time.now.in_time_zone(@tz)
      send_timetable(today, false,person,event.channel)
    end
    return nil
end

#User Create command
@bot.command(:setTimetable, description: "Stores your calendar file on pastebin into the bot's database", usage: "setTimetable [pastebin Raw URL]", min_args: 1, max_args: 1) do |event, timetable_url|
    uri = URI(timetable_url)
    pastebin = Net::HTTP.get_response(uri)
    if (pastebin.code != "200")
      next "Invalid pastebin URI / Pastebin is down, try again."
    else
      begin
        init_user(event.author.id.to_s, pastebin.body)
      rescue
        next "Invalid calendar format. Please re-upload your swinburne calendar and try again"
      else
        "Your calendar is saved. View your timetable today by typing `s.timetable`."
      end
    end
end

#User Delete command
@bot.command(:delete, description: "Delete all of your timetable from the bot's database", usage: "delete") do |event|
    user = event.author.id.to_s
    return delete_user(user)
end

#Class View command
@bot.command(:viewClass, description: "View a class", usage: "viewClass [class-id]", min_args: 1, max_args: 1) do |event, class_id|
  class_node = ClassNode.find(class_id)

  message = ""

  if (class_node.nil?)
    return "No class found"
  end

  message += "Class name: " + class_node.class_name + "\n"
  message += "Class day of week: " + class_node.class_day + "\n"
  message += "Class time: " + class_node.class_time + "\n"
  message += "Class location: " + class_node.class_location + "\n"

  message += "Class on days:\n"

  class_node.date_nodes.order(:date_today).each do |date_node|
    message += date_node.date_today + ", "
  end
  return message
end

#Class List command
@bot.command(:listClasses, description: "List all classes and its uuid", usage: "listClasses [page]", min_args: 1, max_args: 1) do |event, page|
    message = ""
    page = page.to_i
    if (page < 1) 
      return "Page must be greater or equal to one"
    end 
    all_classes = ClassNode.all.order(:class_name)
    max_page = (all_classes.length / 10.0).ceil

    all_classes.skip((page-1)*10).limit(10).each do |class_node|
      message += class_node.class_name + " - " + class_node.class_day + " - " + class_node.class_time + "\n"
      message += "Class id: " + class_node.id + "\n\n"
    end

    message+="Page #{page}/#{max_page}"
    return page <= max_page ? message : "Max page exceeded"
end

#Database Cleanup command
@bot.command(:deleteOldDates, description: "Delete old dates and classes from the previous years", usage: "deleteOldDates", required_permissions: [Perms::MODERATOR.to_sym]  , permission_message: "Not enough permissions") do |event|
  DateNode.all.where(date_today: /^(?!2021).+/i).each do |date_node|
    date_node.class_nodes.each do |class_nodes|
      class_nodes.destroy
    end

    date_node.destroy
  end

  return "Success"
end

@bot.command(:deleteClass, description: "Delete the class from the database and unenroll every student from that class", usage: "deleteClass [class-id]") do |event, class_id|
  class_node = ClassNode.find(class_id)
  if (class_node.nil?)
    return "No classes found"
  end
  class_node.destroy
  return "Success"
end

#Enroll Class command
@bot.command(:enrollClass, description: "Enroll yourself into an existing class", usage: "enrollClass [class-id]", min_args: 1, max_args: 1) do |event, class_id|
  class_node = ClassNode.find(class_id)
  user_id = event.author.id.to_s
  if (class_node.nil?)
    return "No class found"
  end

  user_node = UserNode.find_or_create_by(user_id: user_id)

  user_node.class_nodes << class_node

  class_node.date_nodes.each do |date_node|
    date_node.user_nodes << user_node
  end
  return "Success"
end

#Unenroll Class command
@bot.command(:unenrollClass, description: "Unenroll yourself from a class you're enrolled in", usage: "unenrollClass [class-id]", min_args: 1, max_args: 1) do |event, class_id|
  user_id = event.author.id.to_s
  user_node = UserNode.find_by(user_id: user_id)
  class_node = ClassNode.find(class_id)
  if (user_node.nil? || class_node.nil?)
    return "No user or class found"
  end
  #Query for relationship between user and class

  begin
    user_node.class_nodes(:c, :r).match_to(class_node).delete_all(:r)
  rescue
    return "User not enrolled in that class"
  else
    return "Success"
  end
end

#Create Class command
@bot.command(:createClass, description: "Create a class on the calendar given the name, the dates, how many lessons it has, and automatically enroll in it", usage: "createClass [class-name] [class-first-lesson] [class-time] [class-location] [total-number-of-lessons] [days-before-repeat]", min_args: 6, max_args: 6) do |event, class_name, class_first_date, class_time, class_location, class_repeats, class_gap|
  user_id = event.author.id.to_s
  user_node = UserNode.find_or_create_by(user_id: user_id)
  first_lesson = DateTime.parse(class_first_date)
  class_day = first_lesson.strftime("%A")
  class_node = ClassNode.create(class_name: class_name.gsub("_", " "), class_day: class_day, class_time: class_time, class_location:class_location.gsub("_", " "))
  user_node.class_nodes << class_node
  for i in 0..class_repeats.to_i-1
    lesson_date = first_lesson + class_gap.to_i * i
    lesson_parsed = lesson_date.strftime("%F")
    date_node = DateNode.find_or_create_by(date_today: lesson_parsed)
    class_node.date_nodes << date_node
    date_node.user_nodes << user_node
  end
  return "Class created. Class UUID: #{class_node.id}"
end

@bot.command(:clearRelationship, description: "Clears duplicate relationships (like enrolling twice in a same class)") do |_event|
  ActiveGraph::Base.query("match ()-[r]->() 
                          match (s)-[r]->(e) 
                          with s,e,type(r) as typ, tail(collect(r)) as coll 
                          foreach(x in coll | delete x)")
  return "Finished"
end

@bot.command(:wipeDatabase, description: "Wipe the entire database") do |_event|
  ActiveGraph::Base.query("match (n) detach delete n")
  return "Finished"
end

#Bot On Ready event call
@bot.ready do |_event|
    @bot.send_message(410752448324567053, "Bot restarted")
end

#Bot schedules ping every day
@scheduler.cron ENV['CRON'] do
    today = Time.now.in_time_zone(@tz)
    send_timetable(today, true,nil, 410752448324567053)
end

@bot.run