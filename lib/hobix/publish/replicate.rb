# Content replication: will replicate and/or update the target with
# the files generated by Hobix
# Can handle (currently) copy via FTP and on local filesystem. Plug of sftp should
# not be hard.
#
# == How to use
#  Add the follozing to your hobix.yaml file:
#
#  - replicate:
#      target: ftp://user:pass@isp.com/foo/bar/
#      production_link: http://www.myisp.com/~me/blog
#
#  production_link is optionnal and has been stolen from Sebastian Kanthak
#  (http://www.kanthak.net/explorations/blog/hobix/staging_hobix.html)
#
#  It allows to change the link to the weblog based on the HOBIX_ENV variable
#  which mean that you can have a local test blog (link set to /home/me/foo/blog/htdocs)
#  for example, and a "production" blog (link is http://www.myisp.com/~me/blog) and it should
#  be uploaded to isp.com/foo/bar/ using given user/pass
#
#  Thus to sum-up: 
#  
#  * If the HOBIX_ENV variable is set to "production", then the link is changed
#    to value of production_link (if available) and the page are uploaded to target
#  * If HOBIX_ENV is not set, then the link is not changed and the page go to htdocs
#
#
#  == TODO
#  - Beautify/simplify code
#  - Potentially add some other "non-generated" files (for example css files..)
#
#  Copyright - Frederick Ros
#  License: same as Ruby's one
#
#  $Id$
#
require 'hobix/base'
require 'net/ftp'
require 'fileutils'

module Publish

  Target = Struct.new( :path, :host, :user, :passwd )

  class PublishReplication < Hobix::BasePublish
    attr_reader :production, :replicator, :weblog
    
    def initialize( blog, hash_opt )
      @weblog = blog
      hash_opt['items'] = nil
      hash_opt['source'] = weblog.output_path
      
      if ENV['HOBIX_ENV'] == "production"
        @production = true
        #
        # Change link if a production one is given
        #
        blog.link = hash_opt['production_link'] || blog.link
      else
        @production = false
      end

      if hash_opt['target'] =~ /^ftp:\/\/([^:]+):([^@]+)@([^\/]+)(\/.*)$/
        tgt = Target.new($4,$3,$1,$2)

        @replicator = ReplicateFtp::new(hash_opt, tgt)
      else
        #
        # File replication
        #
        tgt = Target.new(hash_opt['target'])
        @replicator = ReplicateFS.new(hash_opt, tgt)	  

      end
    end

    def watch
      ['index']
    end

    def publish( page_name )
      return unless production
      replicator.items = weblog.updated_pages.map { |o| o.link }
      replicator.copy do |nb,f,src,tgt|
        puts "## Replicating #{src}"
      end
    end

  end
end

module Hobix
  class Weblog
    attr_reader :updated_pages
    
    alias p_publish_orig p_publish

    def p_publish( obj )
      @updated_pages ||= []
      @updated_pages << obj
      p_publish_orig( obj )
    end

  end
end

class Replicate

  attr_accessor :items, :target, :source

  def initialize(hash_src, hash_tgt)
    @items = hash_src['items']
    @source = hash_src['source']
    @target = hash_tgt['path']

  end


  DIRFILE = /^(.*\/)?([^\/]*)$/

  def get_dirs
    dirs = Array.new

    dirfiles = items.collect do |itm|
      dir,file =  DIRFILE.match(itm).captures

      if dir && dir.strip.size != 0
	dirs.push dir
      end
    end
    
    dirs
  end

  def get_files
    files = Array.new
    dirfiles = items.collect do |itm|
      dir,file =  DIRFILE.match(itm).captures

      if file && file.strip.size != 0
	files.push itm
      end
    end
    
    files
  end

  def check_and_make_dirs
    dirs = get_dirs

    dirs.each do |dir|
      # Check existence and create if not present
      dir = File.join(target,dir)
      if !directory?(dir) 
	# Let's create it !
	mkdir_p(dir)
      end
    end      
  end


  def copy_files ( &block)
    files = get_files

    nb_files = files.size

    files.each do |file|

      src_f = File.join(source,file)
      tgt_f = File.join(target,file)
	
      if block_given?
	yield nb_files,file, src_f, tgt_f
      end

      cp(src_f,tgt_f)      
    end
  end


  def copy (&block)
    if respond_to?(:login)
      send :login
    end

    check_and_make_dirs

    copy_files &block

    if respond_to?(:logout)
      send :logout
    end

  end

end


class ReplicateFtp < Replicate

  attr_accessor :ftp, :passwd, :user, :host

  def initialize(hash_src, hash_tgt) 
    super(hash_src,hash_tgt)

    @user = hash_tgt['user']
    @passwd = hash_tgt['passwd']
    @host = hash_tgt['host']

  end

  def login
    @ftp = Net::FTP.open(host)
    ftp.login user,passwd
  end

  def logout
    ftp.close
  end

  def directory?(d)
    old_dir = ftp.pwd

    begin
      ftp.chdir d
      # If we successfully change to d, we could now return to orig dir
      # otherwise we're in the rescue section ...
      ftp.chdir(old_dir)
      return true

    rescue Net::FTPPermError
      if $!.to_s[0,3] == "550"
	# 550 : No such file or directory
	return false
      end
      raise Net::FTPPermError, $!
    end
  end


  def mkdir_p(tgt)
    old_dir = ftp.pwd
    tgt.split(/\/+/).each do |dir|
      next if dir.size == 0
      # Let's try to go down
      begin
	ftp.chdir(dir)
	# Ok .. So it was already existing ..
      rescue Net::FTPPermError
	if $!.to_s[0,3] == "550"
	  # 550 : No such file or directory : let's create ..
	  ftp.mkdir(dir)
	  # and retry
	  retry
	end
	raise Net::FTPPermError, $!
      end
    end
    ftp.chdir(old_dir)

  end


  def cp(src,tgt)
    ftp.putbinaryfile src, tgt
  end
end

class ReplicateFS < Replicate

  def directory?(d)
    File.directory? d
  end

  def mkdir_p(tgt)
    FileUtils.mkdir_p tgt
  end

  def cp(src,tgt)
    FileUtils.cp src, tgt
  end

end