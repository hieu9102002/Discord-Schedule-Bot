require 'active_graph'
require 'icalendar'
require 'stringio'
require './remove_rdate'
require 'icalendar-recurrence'
require 'date'
require 'active_support/time'
require 'json'

class UserNode
  include ActiveGraph::Node
  include ActiveGraph::Timestamps

  property :user_id
  has_many :in, :class_nodes, origin: :user_nodes

  has_many :out, :date_nodes, type: :date_nodes
end

class ClassNode
  include ActiveGraph::Node
  include ActiveGraph::Timestamps

  property :class_name
  property :class_day
  property :class_time
  property :class_location

  has_many :out, :user_nodes, type: :user_nodes

  has_many :in, :date_nodes, origin: :class_nodes
end

class DateNode
  include ActiveGraph::Node
  include ActiveGraph::Timestamps

  property :date_today

  has_many :in, :user_nodes, origin: :date_nodes
  has_many :out, :class_nodes, type: :class_nodes
end

def init_user(id, timetable_file)
  cal = Icalendar::Calendar.parse(remove_rdate(timetable_file)).first
  puts "parsing complete!"

  user_node = UserNode.find_or_create_by(user_id: id)

  cal.events.each_with_index do |classes, index|
    class_name = classes.summary.to_s
    class_day = classes.dtstart.in_time_zone("Australia/Melbourne").strftime("%A")
    class_time = classes.dtstart.in_time_zone("Australia/Melbourne").strftime("%k:%M")
    class_location = classes.location.to_s

    class_node = ClassNode.find_or_create_by(class_name: class_name, class_day: class_day, class_time: class_time, class_location:class_location)

    user_node.class_nodes << class_node

    classes.all_occurrences().each do |occurrence|
      class_date = occurrence.start_time.in_time_zone("Australia/Melbourne").strftime("%F")
      
      date_node = DateNode.find_or_create_by(date_today:class_date)

      class_node.date_nodes << date_node
      date_node.user_nodes << user_node
    end
  end
  ActiveGraph::Base.query("match ()-[r]->() 
                          match (s)-[r]->(e) 
                          with s,e,type(r) as typ, tail(collect(r)) as coll 
                          foreach(x in coll | delete x)")
end

def test()
  ActiveGraph::Base.driver = Neo4j::Driver::GraphDatabase.driver('bolt://localhost:7687', Neo4j::Driver::AuthTokens.basic('neo4j','Huong@897049'))

  puts("Connected with db")
  timetable_file = File.open("swinburne-student-timetable-smith.ics")
  init_user("1212314123432", timetable_file.read)
  timetable_file.close()
end

#test()