module BusinessTime

  class BusinessHours
    include Comparable
    attr_reader :hours

    def initialize(hours, options={})
      @hours = hours
    end

    def <=>(other)
      if other.class != self.class
        raise ArgumentError.new("#{self.class.to_s} can't be compared with #{other.class.to_s}")
      end
      self.hours <=> other.hours
    end

    def ago(options={})
      Time.zone ? before(Time.zone.now, options) : before(Time.now, options)
    end

    def from_now(options={})
      Time.zone ?  after(Time.zone.now, options) : after(Time.now, options)
    end

    def after(time, options={})
      non_negative_hours? ? calculate_after(time, @hours, options) : calculate_before(time, -@hours, options)
    end
    alias_method :since, :after

    def before(time, options={})
      non_negative_hours? ? calculate_before(time, @hours, options) : calculate_after(time, -@hours, options)
    end

    private

    def non_negative_hours?
      @hours >= 0
    end

    def calculate_after(time, hours, options={})
      after_time = Time.roll_forward(time, options)

      # Step through the hours, skipping over non-business hours
      hours.times do |time|
        bod, eod = Time.work_day_boundaries(after_time, options)
        eo_prev_day = Time.end_of_previous_day(after_time, options)
        bo_next_day = Time.beginning_of_next_day(after_time, options)
        after_time = after_time + 1.hour

        delta = 0
        if bod.nil?
          if after_time >= eo_prev_day
            # rolled over midnight into non-business day
            delta = after_time.min * 60 + after_time.sec
            after_time = bo_next_day
          end
        elsif after_time > eod
          delta = after_time - eod
          after_time = bo_next_day
        elsif after_time < bod && after_time >= eo_prev_day
          delta = after_time - eo_prev_day
          after_time = bod
        end

        delta = 0 if delta == 1.second
        after_time = after_time + delta
      end

      after_time
    end

    def calculate_before(time, hours, options={})
      before_time = Time.roll_backward(time, options)
      # Step through the hours, skipping over non-business hours
      hours.times do
        bod, eod = Time.work_day_boundaries(before_time, options)
        eo_prev_day = Time.end_of_previous_day(before_time, options)
        before_time = before_time - 1.hour

        delta = 0
        if bod.nil?
          if before_time >= eo_prev_day
            # rolled over midnight into non-business day
            # delta is how much time past midnight we went
            delta += (60 - before_time.min) * 60 if before_time.min > 0
            delta += (60 - before_time.sec) if before_time.sec > 0

            before_time = eo_prev_day
          end
        elsif before_time < bod && before_time > eo_prev_day
          delta = bod - before_time
          before_time = eo_prev_day
        elsif before_time > eod
          delta = before_time - eod
          before_time = eod
        end

        before_time = before_time - delta

        # Due to the 23:59:59 end-of-workday exception
        before_time += 1.second if before_time.iso8601 =~ /59:59/
      end

      before_time
    end
  end
end
