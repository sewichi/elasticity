module Elasticity

  class EBSConfiguration

    MAX_VOLUME_SIZE_MB = 16 * (2 ** 10) # 16 TB
    VALID_VOLUME_TYPES = %w(gp2 io1 standard sc1 st1)

    def self.from_opts(ebs_opts = {})
      if (ebs_opts[:ebs_size_in_gb].nil? || ebs_opts[:ebs_optimized].nil? || ebs_opts[:ebs_volume_type].nil? || ebs_opts[:ebs_number_of_volumes].nil?)
        raise ArgumentError, "Missing EBS parameters. Passed: #{ebs_opts}"
      end

      ebs_opts[:ebs_size_in_gb] = ebs_opts[:ebs_size_in_gb].to_i
      if ebs_opts[:ebs_iops]
        ebs_opts[:ebs_iops] = ebs_opts[:ebs_iops].to_i
      end

      ebs_opts[:ebs_number_of_volumes] = ebs_opts[:ebs_number_of_volumes].to_i

      if ebs_opts[:ebs_size_in_gb] <= 0
        raise ArgumentError, "EBS Size must be greater than 0 to add an EBS volume (#{ebs_opts[:ebs_size_in_gb]} requested)"
      end

      if ebs_opts[:ebs_number_of_volumes] < 1
        raise ArgumentError, "Must have at least one EBS volume (#{ebs_opts[:ebs_number_of_volumes]} requested)"
      end

      if ebs_opts[:ebs_size_in_gb] > MAX_VOLUME_SIZE_MB
        raise ArgumentError, "EBS Size must be less than #{MAX_VOLUME_SIZE_MB} to add an EBS volume (#{ebs_opts[:ebs_size_in_gb]} requested)"
      end

      if ebs_opts[:ebs_optimized] && ebs_opts[:ebs_size_in_gb] < 10
        raise ArgumentError, "EBS Size must be at least 10 if ebs_optimized (#{ebs_opts[:ebs_size_in_gb]} requested)"
      end

      if !VALID_VOLUME_TYPES.include?(ebs_opts[:ebs_volume_type])
        raise ArgumentError, "EBS Volume Type is not a supported type (#{ebs_opts[:ebs_volume_type]} requested)"
      end

      if ebs_opts[:ebs_volume_type] == 'io1'
        if ebs_opts[:ebs_iops].nil?
          raise ArgumentError, "#{ebs_opts[:ebs_volume_type]} volume type requires iops to be set"
        end
      elsif ebs_opts[:ebs_iops]
        raise ArgumentError, "Iops not supported with #{ebs_opts[:ebs_volume_type]} volume type"
      end

      volume_specification = {
        :volume_type => ebs_opts[:ebs_volume_type],
        :size_in_GB => ebs_opts[:ebs_size_in_gb]
      }

      if ebs_opts[:ebs_iops]
        volume_specification[:iops] = ebs_opts[:ebs_iops]
      end

      {
        :ebs_block_device_configs => [
          {
            :volumes_per_instance => ebs_opts[:ebs_number_of_volumes],
            :volume_specification => volume_specification
          }
        ],
        :ebs_optimized => ebs_opts[:ebs_optimized]
      }
    end

  end

end
