class FQuery

  def [](*names)
    if names.length == 0
      childByAutoId
    else
      childByAppendingPath(names.join('/'))
    end
  end

  def freshRef
    Firebase.alloc.initWithUrl("https://#{repo.repoInfo.host}#{path.toString}")
  end

  def ref_description
    "https://#{repo.repoInfo.host}#{path.toString}##{queryParams.queryIdentifier}"
  end

end
