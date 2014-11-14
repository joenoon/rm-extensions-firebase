class Firebase

  # will sendNext with authData or error
  def rac_authWithCustomTokenSignal(token)
    RACSignal.createSignal(->(subscriber) {
      opts = {}
      noAuthDataError = NSError.errorWithDomain("noAuthDataError", code:0, userInfo:nil)
      authWithCustomToken(token, withCompletionBlock:->(error, authData) {
        if error
          subscriber.sendError(error)
        elsif !opts[:disposed]
          opts[:handle] = observeAuthEventWithBlock(->(_authData) {
            if _authData
              subscriber.sendNext(_authData)
            else
              subscriber.sendError(noAuthDataError)
            end
          })
        end
      })
      RACDisposable.disposableWithBlock(-> {
        opts[:disposed] = true
        if handle = opts[:handle]
          removeAuthEventObserverWithHandle(handle)
        end
      })
    })
  end

end
