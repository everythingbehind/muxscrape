#!/usr/bin/env ruby 
require 'rubygems'
require 'open-uri'
require 'hpricot'
require 'sqlite3'
require 'trollop'

class MuxtapeDatabase

  def initialize(recreate_table=false)
    @db = SQLite3::Database.new( "muxtape.db" )
    begin
      drop_table if recreate_table
      @db.query( 
      %{
        CREATE TABLE muxtapes(
          name varchar(20) primary key, 
          title varchar(50),
          description varchar(200), 
          url varchar(100), 
          fans integer);
      }) 
    rescue SQLite3::SQLException
    end
  end
  
  def drop_table
    begin
      @db.query( 
      %{
        DROP TABLE muxtapes;
      }) 
    rescue SQLite3::SQLException
    end
  end
  
  def muxtape_exists?(muxtape_url)
    @db.get_first_value(
    %{
      SELECT COUNT(*) FROM muxtapes
      WHERE name = ?;
    },
    muxtape_url
    ).to_i > 0
  end
  
  def create_muxtape(name, title, description, url, fans)
    @db.execute(
    %{
      INSERT INTO muxtapes(name, title, description, url, fans)
      VALUES(?, ?, ?, ?, ?);
    }, name, title, description, url, fans)
  end
  
  def update_fans(name, fans)
    @db.execute(
    %{
      UPDATE muxtapes
      SET fans = ?
      WHERE name = ?;
    }, fans, name)
  end
  
  def get_fans(name)
    @db.get_first_value(
    %{
      SELECT fans
      FROM muxtapes
      WHERE name = ?;
    }, name)
  end
end

opts = Trollop::options do
  opt :refreshes, "How many times to refresh the muxtape.com page", :default => 10
end

refreshes = opts[:refreshes]
db = MuxtapeDatabase.new(true)

refreshes.times do
  p "Reloading muxtape.com..."
  doc = Hpricot(open("http://www.muxtape.com"))
  link_total = doc.search("ul.featured").search("a").length
  count = 0
  doc.search("ul.featured").search("a") do |link|
    begin
      link_url = link.attributes['href']
      name = link.inner_html
      muxtape = Hpricot(open(link_url))
      title = muxtape.at('div.flag/h1') && muxtape.at('div.flag/h1').inner_html
      description = muxtape.at('div.flag/h2') && muxtape.at('div.flag/h2').inner_html
      fans = muxtape.at('a.drawer_control') && muxtape.at('a.drawer_control').inner_html
      fan_count = fans ? fans.split.first.to_i : 0
      if !db.muxtape_exists?(name)
        puts "Adding #{name}'s muxtape to database"
        db.create_muxtape(name, title, description, link_url, fan_count)
      else
        puts "Updating #{name}'s muxtape in database"
        db.update_fans(name, fan_count)
      end
      count = count + 1
      p "#{count}/#{link_total} links fetched"
    rescue
      p "Error occured...ignoring"
    end
  end
end