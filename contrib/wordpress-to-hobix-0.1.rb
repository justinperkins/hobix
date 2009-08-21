#!/usr/bin/env ruby
# friends, romans, wordpress, lend me your posts
# (c) 2005 bitserf of http://blog.xeraph.org

require 'fileutils'
require 'mysql'
require 'optparse'

# global defaults
$hobix_author = 'you'
$db_host = nil
$db_user = nil
$db_passwd = nil
$db_db = 'wordpress'

class String
  def ucfirst
    return self if !self || self.empty?
    self[0..0].upcase + self[1..-1]
  end
end

class PersuaderTron
  def initialize(row)
    @row = row
  end

  def hobix_title_name
    a = @row['post_title'].split
    a1 = a[1..-1]
    (a[0] + a1.map{|x| x.ucfirst}.join("")).gsub(/[^a-zA-Z0-9]+/, "")
  end

  def hobix_title
    @row['post_title']
  end

  def hobix_created
    "#{@row['post_date']} +00:00"
  end

  def hobix_summary
    hobixify(@row['post_excerpt'])
  end

  def hobix_content
    hobixify(@row['post_content'])
  end

  def hobixify(content)
    return nil unless content && !content.empty?
    # cheap and nasty HTML-to-textile: blockquotes, lists and anything
    # complex is not handled
    content.gsub!(/\r/, '') # wordpress likes this crap!
    content.gsub!(/<b>(.*?)<\/b>/m, '*\1*')
    content.gsub!(/<strong>(.*?)<\/strong>/m, '*\1*')
    content.gsub!(/<em>(.*?)<\/em>/m, '_\1_')
    content.gsub!(/<i>(.*?)<\/i>/m, '_\1_')
    content.gsub!(/<code>(.*?)<\/code>/m, '@\1@')
    while m = content.match(/<pre>(.*?)<\/pre>/m)
      block = $1
      break if block =~ /^\s*<code>/m
      block = block.split(/\n/).map{|x| "  #{x}"}.join("\n")
      break unless content.sub!(/<pre>(.*?)<\/pre>/m, "<pre>\n<code>\n#{block}\n</code>\n</pre>")
    end
    content.gsub!(/<tt>(.*?)<\/tt>/m, '@\1@')
    content.gsub!(/<del>(.*?)<\/del>/m, '-\1-')
    content.gsub!(/<ins>(.*?)<\/ins>/m, '+\1+')
    content.gsub!(/<sup>(.*?)<\/sup>/m, '^\1^')
    content.gsub!(/<sub>(.*?)<\/sub>/m, '~\1~')
    content.gsub!(/<p>(.*?)<\/p>/m, '\1')
    content.gsub!(/<h(\d+)>(.*?)<\/h1>/m, 'h\1. \2')
    content.split(/\n/).map{|x| "  #{x}"}.join("\n")
  end

  def coerce(outdir)
    post = %Q[--- !okay/news/entry#1.0
title: #{hobix_title}
author: #{$hobix_author}
created: #{hobix_created}
content: >
#{hobix_content}
]
    post += "\nsummary: >\n#{hobix_summary}" if hobix_summary
    FileUtils.mkdir_p outdir
    yamlfile = File.join(outdir, "#{hobix_title_name}.yaml")
    puts "writing: #{yamlfile}"
    File.open(yamlfile, "w+") do |f|
      f.write(post)
    end
  end
end

# lets blow this bitch
parser = OptionParser.new do |o|
  o.banner = "usage: #{$0} [options] OUTPUTDIR"
  o.separator "mysql options:"
  o.on("-h", "--host HOST", "mysql host") {|h| $db_host = h}
  o.on("-u", "--user USER", "mysql username") {|u| $db_user = u}
  o.on("-p", "--password PASSWORD", "mysql password") {|p| $db_passwd = p}
  o.on("-d", "--database DATABASE", "mysql database (default: #{$db_db})") {|d| $db_db = d}
  o.separator "hobix options:"
  o.on("-a", "--author AUTHOR", "force all posts to have this author (default: #{$hobix_author})") {|a| $hobix_author = a}
  o.on("--help", "show this screen") {puts o; exit 0}
end
args = ARGV
parser.parse!(args)
outdir = args.shift
if outdir.nil?
  $stderr.puts parser
  exit 1
end

mysql = Mysql.init
begin
  mysql.connect($db_host, $db_user, $db_passwd, $db_db)
rescue Mysql::Error
  $stderr.puts "error: failed to connect to '#{$db_db}' database: #{$!}"
  exit 1
end
begin
  mysql.query("select * from wp_posts where post_status='publish' order by post_date desc").each_hash do |row|
    tron = PersuaderTron.new(row)
    tron.coerce(outdir)
  end
ensure
  mysql.close
end

__END__
+-----------------------+--------------------------------------------+------+-----+---------------------+----------------+
| Field                 | Type                                       | Null | Key | Default             | Extra          |
+-----------------------+--------------------------------------------+------+-----+---------------------+----------------+
| ID                    | int(10) unsigned                           |      | PRI | NULL                | auto_increment |
| post_author           | int(4)                                     |      |     | 0                   |                |
| post_date             | datetime                                   |      | MUL | 0000-00-00 00:00:00 |                |
| post_date_gmt         | datetime                                   |      | MUL | 0000-00-00 00:00:00 |                |
| post_content          | text                                       |      |     |                     |                |
| post_title            | text                                       |      |     |                     |                |
| post_category         | int(4)                                     |      |     | 0                   |                |
| post_excerpt          | text                                       |      |     |                     |                |
| post_lat              | float                                      | YES  |     | NULL                |                |
| post_lon              | float                                      | YES  |     | NULL                |                |
| post_status           | enum('publish','draft','private','static') |      | MUL | publish             |                |
| comment_status        | enum('open','closed','registered_only')    |      |     | open                |                |
| ping_status           | enum('open','closed')                      |      |     | open                |                |
| post_password         | varchar(20)                                |      |     |                     |                |
| post_name             | varchar(200)                               |      | MUL |                     |                |
| to_ping               | text                                       |      |     |                     |                |
| pinged                | text                                       |      |     |                     |                |
| post_modified         | datetime                                   |      |     | 0000-00-00 00:00:00 |                |
| post_modified_gmt     | datetime                                   |      |     | 0000-00-00 00:00:00 |                |
| post_content_filtered | text                                       |      |     |                     |                |
| post_parent           | int(11)                                    |      |     | 0                   |                |
+-----------------------+--------------------------------------------+------+-----+---------------------+----------------+
