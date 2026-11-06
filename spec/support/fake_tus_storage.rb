class FakeTusStorage
  attr_reader :objects, :infos

  def initialize
    @objects = {}
    @infos = {}
  end

  def create_file(id, info)
    objects[id] = +""
    info["multipart_id"] = "test-upload"
    info["multipart_parts"] = []
  end

  def update_info(id, info)
    infos[id] = Marshal.load(Marshal.dump(info))
  end

  def read_info(id)
    raise Tus::NotFound unless infos.key?(id)

    Marshal.load(Marshal.dump(infos.fetch(id)))
  end

  def patch_file(id, input, info)
    chunk = input.read
    objects.fetch(id) << chunk
    info["multipart_parts"] << { "part_number" => info.fetch("multipart_parts").size + 1, "etag" => "etag" }
    chunk.bytesize
  end

  def finalize_file(_id, info)
    info.delete("multipart_id")
    info.delete("multipart_parts")
  end

  def bucket
    self
  end

  def prefix
    "uploads/tus"
  end

  def object(key)
    FakeObject.new(self, key)
  end

  class FakeObject
    def initialize(storage, key)
      @storage = storage
      @key = key
    end

    def put(body:)
      @storage.objects[@key.split("/").last] = body
    end

    def delete
      @storage.infos.delete(@key.split("/").last.delete_suffix(".info"))
    end

    def exists?
      @storage.objects.key?(@key.split("/").last)
    end

    def content_length
      @storage.objects.fetch(@key.split("/").last).bytesize
    end
  end
end
