module Elasticity

  class JobFlow

    attr_accessor :action_on_failure
    attr_accessor :aws_access_key_id
    attr_accessor :aws_secret_access_key
    attr_accessor :ec2_key_name
    attr_accessor :name
    attr_accessor :hadoop_version
    attr_accessor :instance_count
    attr_accessor :log_uri
    attr_accessor :master_instance_type
    attr_accessor :slave_instance_type

    def initialize(access, secret)
      @action_on_failure = 'TERMINATE_JOB_FLOW'
      @aws_access_key_id = access
      @aws_secret_access_key = secret
      @ec2_key_name = 'default'
      @hadoop_version = '0.20'
      @instance_count = 2
      @master_instance_type = 'm1.small'
      @name = 'Elasticity Job Flow'
      @slave_instance_type = 'm1.small'

      @bootstrap_actions = []
      @jobflow_steps = []
      @installed_steps = []
    end

    def instance_count=(count)
      raise ArgumentError, 'Instance count cannot be set to less than 2 (requested 1)' unless count > 1
      @instance_count = count
    end

    def add_bootstrap_action(bootstrap_action)
      @bootstrap_actions << bootstrap_action
    end

    def add_step(jobflow_step)
      @jobflow_steps << jobflow_step
    end

    private

    def jobflow_config
      config = jobflow_preamble
      config[:steps] = jobflow_steps
      config[:log_uri] = @log_uri if @log_uri
      config[:bootstrap_actions] = @bootstrap_actions.map{|a| a.to_aws_bootstrap_action} unless @bootstrap_actions.empty?
      config
    end

    def jobflow_preamble
      {
        :name => @name,
        :instances => {
          :ec2_key_name => @ec2_key_name,
          :hadoop_version => @hadoop_version,
          :instance_count => @instance_count,
          :master_instance_type => @master_instance_type,
          :slave_instance_type => @slave_instance_type,
        }
      }
    end

    def jobflow_steps
      steps = []
      @jobflow_steps.each do |step|
        if step.class.send(:requires_installation?) && !@installed_steps.include?(step.class)
          steps << step.class.send(:aws_installation_step)
          @installed_steps << step.class
        end
        steps << step.to_aws_step(self)
      end
      steps
    end

  end

end