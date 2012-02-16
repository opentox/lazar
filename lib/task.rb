require File.join(File.dirname(__FILE__),'spork')
DEFAULT_TASK_MAX_DURATION = 36000
module OpenTox

  # Class for handling asynchronous tasks
  class Task

    def self.create service_uri, params={}
      task = Task.new RestClient.post(service_uri,params).chomp
      pid = Spork.spork do
        begin
          task.completed yield 
        rescue => error
          task.error error
        end
      end
      task.pid = pid
      task
    end

    def description
      metadata[RDF::DC.description]
    end
    
    def cancel
      RestClient.put(File.join(@uri,'Cancelled'),{})
    end

    def completed(uri)
      RestClient.put(File.join(@uri,'Completed'),{:resultURI => uri})
    end

    def error(error)
      RestClient.put(File.join(@uri,'Error'),{:errorReport => OpenTox::Error.new(error)})
    end

    # waits for a task, unless time exceeds or state is no longer running
    # @param [optional,Numeric] dur seconds pausing before cheking again for completion
    def wait_for_completion(dur=0.3)
      due_to_time = Time.new + DEFAULT_TASK_MAX_DURATION
      while self.running?
        sleep dur
        raise "max wait time exceeded ("+DEFAULT_TASK_MAX_DURATION.to_s+"sec), task: '"+@uri.to_s+"'" if (Time.new > due_to_time)
      end
    end
  end

  def method_missing(method,*args)
    method = method.to_s
    begin
      case method
      when /=/
        res = RestClient.put(File.join(@uri,method.sub(/=/,'')),{})
        super unless res.code == 200
      when /\?/
        return hasStatus == method.sub(/\?/,'').capitalize
      else
        return metadata[RDF::OT[method]].to_s
      end
    rescue
      super
    end
  end

  #TODO: subtasks

end
