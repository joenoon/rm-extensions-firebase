class Firebase

  def rmx_object_desc
    "#{super}:#{description}"
  end

  def [](*names)
    if names.length == 0
      childByAutoId
    else
      childByAppendingPath(names.join('/'))
    end
  end

  def limited(limit)
    queryLimitedToNumberOfChildren(limit)
  end

  def starting_at(priority, child_name=nil)
    if child_name
      queryStartingAtPriority(priority, andChildName:child_name)
    else
      queryStartingAtPriority(priority)
    end
  end

  def ending_at(priority, child_name=nil)
    if child_name
      queryEndingAtPriority(priority, andChildName:child_name)
    else
      queryEndingAtPriority(priority)
    end
  end

  # will sendNext with authData or error
  def rmx_authWithCredentialSignal(firebase_auth)
    RACSignal.createSignal(->(subscriber) {
      authWithCredential(firebase_auth, withCompletionBlock:->(error, authData) {
        if error
          subscriber.sendError(error)
        else
          subscriber.sendNext(authData)
        end
      }, withCancelBlock:->(error) {
        subscriber.sendError(error)
      })
      nil
    })
  end

end
