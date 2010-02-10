#!/usr/bin/env script/runner
# usage:
# rm db/seed/*
# RAILS_ENV=production script/dump.rb

SEEDS = ["Sidra", "astolat", "Enigel", "hope", "awils1", 
         "Cesy", "elz", "justira", "lim", "melange", 
          "rklyne", "zelempa"] # users who have webdavs
ADD_EXTERNAL = true
NTH = 20

#### to dump just one user (e.g. Enigel):
#  SEEDS = [ "Enigel" ]
#  ADD_EXTERNAL = false 
#  NTH = 1
#### note, this will dump all their comments and bookmarks, but not the associated works


#### end of configuration

TAGGABLES = []
WORKS = []

def add_pseuds(pseuds)
  x = []
  pseuds.flatten.compact.uniq.each do |p|
    x << p
    x << p.user
    x << p.user.preference
  end
  x.flatten.compact.uniq
end

def add_tags(items)
  x = []
  taggables = items.select{|i| i.respond_to?("tags")}.uniq
  puts " finding taggings"
  taggings = taggables.map(&:taggings).flatten.compact.uniq
  x << taggings
  puts " finding tags"
  tags = taggables.map(&:tags).flatten.compact.uniq
  x << tags
  puts " finding synonyms for #{tags.size} tags"
  merger_ids = tags.map(&:merger_id).compact.uniq
  x << Tag.find_all_by_id(merger_ids)
  puts " finding associations"
  common_taggings = CommonTagging.find_all_by_common_tag_id_and_filterable_type(tags.map(&:id), "Tag")
  x << common_taggings
  puts " finding parents"
  common_tags = Tag.find_all_by_id(common_taggings.map(&:filterable_id))
  x << common_tags
  puts "Dumping records for tags"
  x.flatten.compact.uniq
end

def add_works(items)
  puts " collecting work associations"
  x = []
  items.each do |work|
    print "."; STDOUT.flush
    TAGGABLES << work
    x << work
    x << add_pseuds(work.pseuds)
    x << work.creatorships
    x << work.chapters
    work.chapters.each do |c|
      x << c.comments
      x << add_pseuds(c.comments.map(&:pseud))
    end
    x << work.collection_items
    x << work.series
    x << work.serial_works
  end
  puts ""
  puts "Dumping records for works"
  x.flatten.compact.uniq
end

def user_records(u)
  x = []
  x << u
  x << u.preference
  x << u.profile
  x << u.pseuds
  u.pseuds.each do |p|
    p.comments.find_in_batches(:batch_size => NTH) do |comments|
      comment = comments.last
      x << comment
      commentable = comment.ultimate_parent
      if ADD_EXTERNAL
        if commentable.is_a?(Work)
          WORKS << commentable
        else
          x << commentable
        end
      end
    end
    p.bookmarks.find_in_batches(:batch_size => NTH) do |batch|
      bookmark = batch.last
      x << bookmark
      bookmarkable = bookmark.bookmarkable
      if bookmarkable.is_a?(Work)
        WORKS << bookmarkable if ADD_EXTERNAL
      else
        TAGGABLES << bookmarkable
        x << bookmarkable if ADD_EXTERNAL
      end
    end
    x << p.creatorships
    p.creatorships.map(&:creation).each do |item|
      if item.is_a?(Work)
        WORKS << item
      elsif item.is_a?(Chapter)
        nil
      else
        TAGGABLES << item
        x << item
      end
    end
    x << p.collections
    p.collections.each do |c|
      x << c.collection_profile
      x << c.collection_preference
      x << c.collection_participants
    end
  end
  u.inbox_comments.find_in_batches(:batch_size => NTH) do |batch|
    inbox_comment = batch.last
    x << inbox_comment
    x << inbox_comment.feedback_comment
    x << add_pseuds([inbox_comment.feedback_comment.pseud])
    thing = inbox_comment.feedback_comment.ultimate_parent
    WORKS << thing if (ADD_EXTERNAL && thing.is_a?(Work))
  end
  u.readings.find_in_batches(:batch_size => NTH) do |readings|
    x << readings.last
    WORKS << readings.last.work if ADD_EXTERNAL
  end 
  x.flatten.compact.uniq
end

def write_model(thing)
  print "."; STDOUT.flush
  klass = thing.class.name
  attributes = thing.attributes
  attributes["email"] = "REDACTED@transformativeworks.org" if attributes["email"]
  # the following is to fix a bug in YAML slurp
  attributes["content"] = attributes["content"].strip if attributes["content"]
  File.open("#{klass.underscore}.yml", 'a') {|f| YAML.dump attributes, f }
end

def dump_user(user)
  puts ""
  puts " #{user.login}'s records"
  user_records(user).each {|x| write_model(x)}
  File.open("roles_users.yml", 'a') do |f|
    user.roles.each do |role|
      attributes = {"user_id" => user.id, "role_id" => role.id}
      YAML.dump attributes, f
    end
  end
end

backupdir = RAILS_ROOT + '/db/seed'
FileUtils.mkdir_p(backupdir)
FileUtils.chdir(backupdir)

puts "Files in #{backupdir}"  
puts ""
puts "Dumping records for roles"  
Role.find_each {|a| write_model(a)}
puts "Dumping records for seeds"  
SEEDS.each {|seed| dump_user(User.find_by_login(seed))}

if ADD_EXTERNAL
  puts ""
  puts "Dumping all admin records to yaml files"
  Admin.find_each {|a| write_model(a)}
  AdminPost.find_each {|p| write_model(p)}
  ArchiveFaq.find_each {|f| write_model(f)}
  KnownIssue.find_each {|ki| write_model(ki)}
  Role.find_each {|r| write_model(r)}
  puts ""
  puts "Dumping every #{NTH} feedback records" 
  Feedback.find_in_batches(:batch_size => NTH ) {|b| write_model(b.last)}

  puts ""
  puts "Dumping every #{NTH} user records"  
  User.find_in_batches(:batch_size => NTH ) {|users| dump_user(users.last) }
end

puts ""
puts "Dumping #{WORKS.compact.uniq.size} works"
add_works(WORKS.compact.uniq).each {|item| write_model(item)}

puts ""
puts "Dumping tags for #{TAGGABLES.size} taggables"
add_tags(TAGGABLES).each {|item| write_model(item)}
puts ""