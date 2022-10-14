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

  public Request.GET (string uri, InstanceAccount? account=null) {
    string url;
    if (account != null) url = make_absolute_url(account.instance, uri); else url = uri;
    this._msg = new Soup.Message ("GET", url);
    if (this._msg == null) {
      message (@"uri could not be parsed $(this._msg != null ? "MSG": "NULL")");
    }
  }
  public Request.POST (string uri, InstanceAccount? account=null) {
    string url;
    if (account != null) url = make_absolute_url(account.instance, uri); else url = uri;
    this._msg = new Soup.Message ("POST", url);
    if (this._msg == null) {
      message (@"uri could not be parsed $(this._msg != null ? "MSG": "NULL")");
    }
  }
  public Request.PUT (string uri, InstanceAccount? account=null) {
    string url;
    if (account != null)
      url = make_absolute_url(account.instance, uri);
      else url = uri;
    this._msg = new Soup.Message ("PUT", url);
    if (this._msg == null) {
      message (@"uri could not be parsed $(this._msg != null ? "MSG": "NULL")");
    }
  }
  public Request.DELETE (string uri, InstanceAccount? account=null) {
    string url;
    if (account != null) url = make_absolute_url(account.instance, uri); else url = uri;
    this._msg = new Soup.Message ("DELETE", url);
    if (this._msg == null) {
      message (@"uri could not be parsed $(this._msg != null ? "MSG": "NULL")");
    }
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

  // check uri and if it is not absolute make it so with the information from .account
  private string make_absolute_url(string base_uri, string uri_str) {
    string res_str;
    message(@"Prejoin URI is $(uri_str), base_uri is $(base_uri)");
    try {
      // parse uri and, if it is a relative URI, resolves it relative to the base_uri_string account.instance
      res_str = Uri.resolve_relative (base_uri, uri_str, GLib.UriFlags.NONE);
    } catch (UriError e) {
      warning ("Error making uri $(uri_str) absolute. Account $(account.instance)");
      res_str = "";
    }
    message(@"Postjoin URI is $(res_str)");
    return (res_str);
  }


  public Request exec () {    
    if (form_data != null) {
      // Replace _msg with new Message from our multipart form, keeping the previous uri
      this._msg = new Soup.Message.from_multipart (this._msg.uri.to_string(), form_data);
    }
    message (@"NOOO msg $(this._msg != null ? "MSG": "NULL")");
    if (account != null) {
      this._msg.request_headers.append ("Authorization", @"Bearer $(account.access_token)");
    }

    var abs_uri_str = this.uri.to_string();

    // Add in our query string
    if (pars != null) {
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
      abs_uri_str = abs_uri_str + query;
    };

    this.uri = Uri.parse(abs_uri_str, GLib.UriFlags.NONE);
    message(@"Finnal URI is $(this.uri)");
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
    info ("Cancelling Network Request");
    if (this.cancellable.is_cancelled ()) {
	     // should not occur?
	     info ("Oops, message was already cancelled.");
    }
    this.cancellable.cancel ();
  }
}
