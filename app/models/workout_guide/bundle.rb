require "json"

class WorkoutGuide::Bundle
  VENDOR_PATH = Rails.root.join("vendor/workout_guide")

  class Error < ArgumentError; end

  class << self
    def vendored
      new(VENDOR_PATH)
    end
  end

  def initialize(root)
    @root = Pathname(root).expand_path
    @records = JSON.parse((@root / "manifest.json").read)
    @release_tag = parse_version.fetch("release_tag")
    @checksums = parse_checksums
  end

  attr_reader :root, :records, :release_tag, :checksums

  def resolve_asset!(relative)
    raise Error, "frame path is required" if relative.to_s.blank?

    candidate = Pathname(relative)
    raise Error, "frame path must be relative" if candidate.absolute?
    raise Error, "frame path escapes the bundle" if candidate.each_filename.include?("..")

    path = @root.join(candidate).expand_path
    raise Error, "frame path escapes the bundle" unless path.to_s.start_with?("#{@root}/")
    raise Error, "missing checksum for #{relative}" unless @checksums.key?(relative.to_s)
    raise Error, "missing frame file #{relative}" unless path.file?

    path
  end

  def checksum_for!(relative)
    @checksums.fetch(relative.to_s) { raise Error, "missing checksum for #{relative}" }
  end

  private
    def parse_version
      (@root / "VERSION").each_line.with_object({}) do |line, parsed|
        key, value = line.split(":", 2)
        parsed[key.strip] = value.to_s.strip if key.present?
      end
    end

    def parse_checksums
      (@root / "CHECKSUMS").each_line.with_object({}) do |line, parsed|
        digest, path = line.strip.split(/\s+/, 2)
        parsed[path] = digest if digest.present? && path.present?
      end
    end
end
