class Cache

  include DataMapper::Resource

  property :id, Serial

  property :sid, Integer

  property :cid, Integer

  property :ran_at, DateTime

  property :event_count, Integer, :default => 0

  property :tcp_count, Integer, :default => 0

  property :udp_count, Integer, :default => 0

  property :icmp_count, Integer, :default => 0

  property :severity_metrics, Object

  property :signature_metrics, Object
  
  property :src_ips, Object
  
  property :dst_ips, Object

  # Define created_at and updated_at timestamps
  timestamps :at

  belongs_to :sensor, :parent_key => :sid, :child_key => :sid

  has 1, :event, :parent_key => [ :sid, :cid ], :child_key => [ :sid, :cid ]

  def self.last_month
    all(:ran_at.gt => (Time.now - 2.months).beginning_of_month, :ran_at.lt => (Time.now - 2.months).end_of_month)
  end

  def self.this_month
    all(:ran_at.gt => Time.now.beginning_of_month, :ran_at.lt => Time.now.end_of_month)
  end

  def self.last_week
    all(:ran_at.gt => (Time.now - 2.weeks).beginning_of_week, :ran_at.lt => (Time.now - 2.weeks).end_of_week)
  end

  def self.this_week
    all(:ran_at.gt => Time.now.beginning_of_week, :ran_at.lt => Time.now.end_of_week)
  end

  def self.yesterday
    all(:ran_at.gt => (Time.now - 1.day).beginning_of_day, :ran_at.lt => (Time.now - 1.day).end_of_day)
  end

  def self.today
    all(:ran_at.gt => Time.now.beginning_of_day, :ran_at.lt => Time.now.end_of_day)
  end

  def self.protocol_count(protocol, type=nil)
    count = []
    @cache = self.group_by { |x| x.ran_at.hour }

    case protocol.to_sym
    when :tcp
      @cache.each do |hour, data|
        count[hour] = data.map(&:tcp_count).sum
      end
    when :udp
      @cache.each do |hour, data|
        count[hour] = data.map(&:udp_count).sum
      end
    when :icmp
      @cache.each do |hour, data|
        count[hour] = data.map(&:icmp_count).sum
      end
    end

    Time.now.beginning_of_day.hour.upto(Time.now.end_of_day.hour) do |i|
      next if count[i]
      count[i] = 0
    end

    count
  end

  def self.severity_count(severity, type=nil)
    count = []
    @cache = self.group_by { |x| x.ran_at.hour }

    case severity.to_sym
    when :high
      @cache.each do |hour, data|
        high_count = 0
        data.map(&:severity_metrics).each { |x| high_count += (x.kind_of?(Hash) ? (x.has_key?(1) ? x[1] : 0) : 0) }
        count[hour] = high_count
      end
    when :medium
      @cache.each do |hour, data|
        medium_count = 0
        data.map(&:severity_metrics).each { |x| medium_count += (x.kind_of?(Hash) ? (x.has_key?(2) ? x[2] : 0) : 0) }
        count[hour] = medium_count
      end
    when :low
      @cache.each do |hour, data|
        low_count = 0
        data.map(&:severity_metrics).each { |x| low_count += ( x.kind_of?(Hash) ? (x.has_key?(3) ? x[3] : 0) : 0) }
        count[hour] = low_count
      end
    end

    Time.now.beginning_of_day.hour.upto(Time.now.end_of_day.hour) do |i|
      next if count[i]
      count[i] = 0
    end

    count
  end

  def self.get_last
    first(:order => [:ran_at.desc])
  end

  def self.sensor_metrics(type=nil)
    @metrics = []

    Sensor.all(:limit => 5, :order => [:events_count.desc]).each do |sensor|
      count = Array.new(24) { 0 }
      blah = self.all(:sid => sensor.sid).group_by { |x| x.ran_at.hour }

      blah.each do |hour, data|
        count[hour] = data.map(&:event_count).sum
      end

      @metrics << { :name => sensor.name, :data => count, :range => 24.times.to_a }
    end

    @metrics
  end
  
  def self.src_metrics(stop_count=10)
    @metrics = {}
    @cache = self.map(&:src_ips).compact
    count = 0
    
    @cache.each do |ip_hash|
      
      return @metrics if count > stop_count.to_i
      
      ip_hash.each do |ip, count|
        if @metrics.has_key?(ip)
          @metrics[ip] += count
        else
          @metrics.merge!({ip => count})
          count += 1
        end
      end
    end
    
    @metrics
  end
  
  def self.dst_metrics(stop_count=10)
    @metrics = {}
    @cache = self.map(&:dst_ips).compact
    count = 0
    
    @cache.each do |ip_hash|
      
      return @metrics if count > stop_count.to_i
      
      ip_hash.each do |ip, count|
        if @metrics.has_key?(ip)
          @metrics[ip] += count
        else
          @metrics.merge!({ip => count})
          count += 1
        end
      end
    end
    
    @metrics
  end

  def self.signature_metrics(stop_count=10)
    @metrics = {}
    @cache = self
    count = 0
    
    @cache.map(&:signature_metrics).each do |data|
      next unless data
      
      return @metrics if count > stop_count.to_i
      
      data.sort_by { |k,v| v <=> v }.each do |id, value|
        if @metrics.has_key?(id)
          temp_count = @metrics[id]
          @metrics.merge!({id => temp_count + value})
        else
          @metrics.merge!({Signature.get(id).sig_name.to_sym => value})
          count += 1
        end
      end
      
    end

    @metrics
  end

end
