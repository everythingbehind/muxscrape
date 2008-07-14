#!/usr/bin/env ruby 
require 'rubygems'
require 'open-uri'
require 'hpricot'
require 'sqlite3'
require 'trollop'

class MuxtapeDatabase

  def initialize(recreate_table=false)
    @db = SQLite3::Database.new("muxtape.db")
    begin
      drop_tables if recreate_table
      @db.execute( 
      %{
        CREATE TABLE muxtapes(
          id integer primary key,
          name varchar(20), 
          title varchar(50),
          description varchar(200), 
          url varchar(100), 
          fans integer);
      }) 
      @db.execute( 
      %{
        CREATE TABLE songs(
          id integer primary key,
          muxtape_id integer,
          artist varchar(100),
          title varchar(100));
      })
    rescue SQLite3::SQLException
      puts 'Database creation error...'
    end
  end
  
  def drop_tables
    begin
      @db.execute( 
      %{
        DROP TABLE muxtapes;
      }) 
      @db.execute( 
      %{
        DROP TABLE songs;
      })
    rescue SQLite3::SQLException
    end
  end
  
  def muxtape_exists?(name)
    @db.get_first_value(
    %{
      SELECT COUNT(*) FROM muxtapes
      WHERE name = ?;
    },
    name
    ).to_i > 0
  end
  
  def create_muxtape(name, title, description, url, fans)
    @db.execute(
    %{
      INSERT INTO muxtapes(name, title, description, url, fans)
      VALUES(?, ?, ?, ?, ?);
    }, name, title, description, url, fans)
    @db.last_insert_row_id
  end
  
  def update_fans(name, fans)
    @db.execute(
    %{
      UPDATE muxtapes
      SET fans = ?
      WHERE name = ?;
    }, fans, name)
  end
  
  def add_songs(muxtape_id, songs)
    songs.each do |song|
      @db.execute(
      %{
        INSERT INTO songs(muxtape_id, artist, title)
        VALUES(?, ?, ?);
      }, muxtape_id, song[:artist], song[:title])
    end
  end
end

class MuxtapeParser
  
  def initialize(link_url)
    @muxtape = Hpricot(open(link_url))
  end
  
  def title
    @muxtape.at('div.flag/h1') && @muxtape.at('div.flag/h1').inner_html
  end
  
  def description
    @muxtape.at('div.flag/h2') && @muxtape.at('div.flag/h2').inner_html
  end
  
  def fan_count
    fans = @muxtape.at('a.drawer_control') && @muxtape.at('a.drawer_control').inner_html
    fans ? fans.split.first.to_i : 0
  end
  
  def songs
    songs = []
    @muxtape.search('li.stripe') do |stripe|
      artist = stripe.at('span.artist') && stripe.at('span.artist').inner_html
      title = stripe.at('span.title') && stripe.at('span.title').inner_html
      songs << {:artist => artist, :title => title}
    end
    songs
  end
  
end

opts = Trollop::options do
  opt :refreshes, "How many times to refresh the muxtape.com page", :default => 10
end

refreshes = opts[:refreshes]
db = MuxtapeDatabase.new

refreshes.times do
  puts "Refreshing muxtape.com..."
  doc = Hpricot(open("http://www.muxtape.com"))
  link_total = doc.search("ul.featured").search("a").length
  count = 0
  doc.search("ul.featured").search("a") do |link|
    begin
      link_url = link.attributes['href']
      name = link.inner_html
      mp = MuxtapeParser.new(link_url)
      
      if !db.muxtape_exists?(name)
        puts "Adding #{name}'s muxtape to database"
        muxtape_id = db.create_muxtape(name, mp.title, mp.description, link_url, mp.fan_count)
        db.add_songs(muxtape_id, mp.songs)
      else
        puts "Updating #{name}'s muxtape in database"
        db.update_fans(name, mp.fan_count)
      end
      count = count + 1
      puts "#{count}/#{link_total} links fetched"
    rescue
      puts "Error occured...ignoring"
    end
  end
end