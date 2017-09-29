require 'nokogiri'
require 'open-uri'
require 'mastodon'
require 'date'
require 'json'
require 'digest/sha2'
require "fileutils"
require 'dotenv'
require 'active_support/all'

Dir.chdir(File.expand_path("../", __FILE__))
Dotenv.load

class Job
  def initialize(date, job, url)
    @date = date
    @job = job
    @src = url
  end

  def read_json
    json = JSON.parse(open(File.expand_path("../json/#{get_year}#{get_month}#{get_date}.json", __FILE__), "r").read, symbolize_names: true)
    @job = json
    p json
  end

  def write_json
    json = File.open(File.expand_path("../json/#{get_year}#{get_month}#{get_date}.json", __FILE__), "w")
    json.puts(@job.to_json)
  end

  def mastodon_post
    contents = @job[:content]
    post = "#{@job[:title]}\n"
    if contents.blank?
      post << "現在、お仕事情報はありません。\nhttp://idolmaster.jp/schedule/\n"
    else
      contents.each do |content|
        post << content[:post]
      end
    end
    post << "#imas_oshigoto"
    client = Mastodon::REST::Client.new(base_url: ENV["MASTODON_URL"], bearer_token: ENV["MASTODON_ACCESS_TOKEN"])
    client.create_status(post)
  end

  def get_dateobj
    @date
  end

  def get_year
    @date.strftime("%Y")
  end

  def get_month
    @date.strftime("%m")
  end

  def get_date
    @date.strftime("%d")
  end

  def get_job
    @job
  end
end

class MonthlyJobs
  def initialize(date)
    @y = date.strftime("%Y")
    @m = date.strftime("%m")
    @first_day = date
    @end_day = date.at_end_of_month
    @src = "http://idolmaster.jp/schedule/?ey=#{@y}&em=#{@m}"
    @joblist = get_daily_jobs
  end

  def write_json(*exclude_days)
    @joblist.each do |job|
      if !exclude_days.nil? && exclude_days.include?("#{job.get_year}#{job.get_month}#{job.get_date}")
        job.read_json
      else
        job.write_json
      end
    end
  end

  def mastodon_post_today
    @joblist.find{ |job|
      job.get_dateobj == Date.today
    }.mastodon_post
  end

  private

  def get_daily_jobs
    begin
      doc = Nokogiri::HTML(open(@src))
    rescue
      return nil
    end

    joblist = []
    tablelist = doc.css("table.List")
    tr = tablelist.css("tr")
    i = 3
    day = @first_day.beginning_of_month
    week = %w[日 月 火 水 木 金 土]

    while day < @first_day
      jobcount = tr[i].css("td")[0].attribute("rowspan").value.to_i
      jobcount.times do
        i += 1
      end
      day = day.tomorrow
    end

    while day <= @end_day
      jobcount = tr[i].css("td")[0].attribute("rowspan").value.to_i
      jobs = {
        date: day,
        title: "【#{day.strftime("%m").to_s}/#{day.strftime("%d").to_s}(#{week[day.wday]})のお仕事】"
      }
      tmp = []
      jobcount.times do
        time = tr[i].css("td.time2").inner_html
        if(time.eql?(""))
          jobcount = 0
          i += 1
          break
        end
        team = tr[i].css("td.performance2")[0].css("img").attribute("alt").value
        content = tr[i].css("td.article2")[0].css("a").inner_html
        url = tr[i].css("td.article2")[0].css("a").attribute("href").value
        jobcode = Digest::SHA256.hexdigest("#{jobs[:title]}\n[#{team}] #{time}\n#{content}\n#{url}\n")[0, 6]
        begin
          t = Time.new(day.strftime("%Y"), day.strftime("%m"), day.strftime("%d"), time.split(":")[0], time.split(":")[1][0, 2])
        rescue
          t = nil
        end
        hastime = (t == nil) ? false : true
        post = (hastime ? "[#{team}] #{time}\n#{content}\n#{url}\nお仕事コード:#{jobcode}\n" : "[#{team}] #{time}\n#{content}\n#{url}\n")
        tmp << { has_time: hastime, time: t.to_s, really_time: time, team: team, item: content, url: url, post: post, code: jobcode }
        i += 1
      end

      jobs.merge!({
        job_count: jobcount,
        content: tmp,
      })
      joblist << Job.new(day, jobs, @src)
      day = day.tomorrow
    end
    joblist
  end
end

this_month = MonthlyJobs.new(Date.today)
this_month.write_json()
this_month.mastodon_post_today
next_month = MonthlyJobs.new(Date.today.next_month.beginning_of_month)
next_month.write_json
