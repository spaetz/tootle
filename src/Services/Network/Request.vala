using Soup;
using Gee;

public class Tootle.Request {
  /* Encapsulates a Soup.Message, represents an HTTP message being sent or received. */

  /* Uri can be a relative or absolute Uri */
  public GLib.Uri? uri {
    get { return (this._msg != null) ? this._msg.uri : null; }
    set { this._msg.uri = value; }
  }
  public string method {
    get { return (this._msg != null) ? this._msg.method : ""; }
    set { this._msg.method = value; }
  }
  // Used to cancel an ongoing msg
  public Cancellable cancellable;

  // Holds the response_body once the response has been read
  public Bytes? response_body;

  public weak InstanceAccount? account { get; set; default = null; }
  public Network.SuccessCallback? cb;
  public Network.ErrorCallback? error_cb;
  HashMap<string, string>? pars;
  Soup.Multipart? form_data;

  public Soup.Message? _msg;
  // read-only access to the underlying Soup.Message
  public Soup.Message? msg {get { return this._msg;}}
	
  weak Gtk.Widget? ctx;
  bool has_ctx = false;

  public Request.GET (string uri) {
    this._msg = new Message ("GET", uri);
    _msg.accept_certificate.connect (this.on_accept_certificate);
  }
  public Request.POST (string uri) {
    this._msg = new Message ("POST", uri);
    _msg.accept_certificate.connect (this.on_accept_certificate);
  }
  public Request.PUT (string uri) {
    this._msg = new Message ("PUT", uri);
    _msg.accept_certificate.connect (this.on_accept_certificate);
  }
  public Request.DELETE (string uri) {
    this._msg = new Message ("DELETE", uri);
    _msg.accept_certificate.connect (this.on_accept_certificate);
  }

	// ~Request () {
	// 	message ("Destroy req: "+url);
	// }

  public Request then (owned Network.SuccessCallback cb) {
    this.cb = (owned) cb;
    return this;
  }

  public Request then_parse_array (owned Network.NodeCallback _cb) {
    this.cb = (sess, req) => {
      Network.parse_array (this, (owned) _cb);
    };
    return this;
  }

  public Request with_ctx (Gtk.Widget ctx) {
    this.has_ctx = true;
    this.ctx = ctx;
    this.ctx.destroy.connect (() => {
	this.cancel ();
	this.ctx = null;
      });
    return this;
  }

  public Request on_error (owned Network.ErrorCallback cb) {
    this.error_cb = (owned) cb;
    return this;
  }

  public Request with_account (InstanceAccount? account = null) {
    this.account = account;
    return this;
  }

  public Request with_param (string name, string val) {
    if (pars == null)
      pars = new HashMap<string, string> ();
    pars[name] = val;
    return this;
  }

  public Request with_form_data (string name, string val) {
    // This will imply "POST" method and override any methods set initially
    if (form_data == null)
      form_data = new Soup.Multipart(FORM_MIME_TYPE_MULTIPART);
    form_data.append_form_string(name, val);
    return this;
  }

  public Request exec () {
    string query = "";
 
    var parameters_counter = 0;
    pars.@foreach (entry => {
	parameters_counter++;
	var key = (string) entry.key;
	var val = (string) entry.value;
	query += @"$key=$val";
	  
	if (parameters_counter < pars.size)
	  query += "&";

	return true;
      });
    
    if (form_data != null) {
      // Replace _msg with new Message from our multipart form, keeping the previous uri
      this._msg = new Soup.Message.from_multipart (this._msg.uri.to_string(), form_data);
    }

    if (account != null) {
      _msg.request_headers.append ("Authorization", @"Bearer $(account.access_token)");
    }

    message(@"Prejoin URI is $(this.uri)");
    // msg.uri can be a relative URL without scheme-host-port _or_ be absolute, so add the host if it is relative
    if (this.uri.get_host() == null)
      try {
	// parse uri and, if it is a relative URI, resolves it relative to the base_uri_string account.instance
	this.uri = Uri.parse_relative (account.instance, this.uri.to_string(), GLib.UriFlags.NONE);
      } catch (UriError e) {
      warning ("Error munging URI %(this.uri.to_string() ?? ''");
    }

    if (query.length > 0) {
      this.uri = Uri.parse(this.uri.to_string() + query, GLib.UriFlags.NONE);
    }
    message(@"Finnal URI is $(uri)");
    network.queue (this, (owned) cb, (owned) error_cb);
    return this;
  }

  public async Request await () throws Error {
    string? error = null;
    this.error_cb = (code, reason) => {
      error = reason;
      await.callback ();
    };
    this.cb = (sess, req) => {
      await.callback ();
    };
    this.exec ();
    yield;
    
    if (error != null)
      throw new Oopsie.INSTANCE (error);
    else
      return this;
  }

  // handler to bail out on cert errors (formerly ssl_strict)
  private bool on_accept_certificate (TlsCertificate certificate, TlsCertificateFlags errors) {
    /* Errors is one of: https://valadoc.org/gio-2.0/GLib.TlsCertificateFlags.html */
    if (errors == 0) {
      // TODO Check for TlsCertificateFlags.NO_FLAGS available since glib : 2.74
      return true;
    }
    /* TODO: handle and inform user about the type of TLS error */
    warning ("Not accepting invalid certificate for %(certificate.get_subject_name() ?? ''");
    return false;
  }

  public static string array2string (Gee.ArrayList<string> array, string key) {
    var result = "";
    array.@foreach (i => {
	result += @"$key[]=$i";
	if (array.index_of (i)+1 != array.size)
	  result += "&";
	return true;
      });
    return result;
  }

  // Cancel an ongoing Soup.Message.
  // TODO: Need to pass this.cancellable actually into cancellable operations
  public void cancel () {
    info ("Cancelling message");
    if (this.cancellable.is_cancelled ()) {
	     // should not occur?
	     info ("Oops, message was already cancelled.");
    }
    this.cancellable.cancel ();
  }
}
