using Soup;
using GLib;
using Gdk;
using Json;

public class Tootle.Network : GLib.Object {

	public signal void started ();
	public signal void finished ();

	public delegate void ErrorCallback (int32 code, string reason);
	public delegate void SuccessCallback (Session session, Tootle.Request req) throws Error;
	public delegate void NodeCallback (Json.Node node, Tootle.Request req) throws Error;
	public delegate void ObjectCallback (Json.Object node) throws Error;

	public Soup.Session session { get; set; }
	// count the number of currently queue requests
	int requests_processing = 0;

	construct {
	  session = new Soup.Session ();

	  session.request_queued.connect (msg => {
	      if (requests_processing == 0) { started (); };
	      requests_processing++;
	  });

	  session.request_unqueued.connect (msg => {
	      requests_processing--;
	      if (requests_processing <= 0) { finished (); };
	  });
	}

	public async void queue (owned Tootle.Request request, owned SuccessCallback cb, owned ErrorCallback ecb) {
		message (@"Queuing $(request.method): $(request.uri.to_string())");

		  // we discard the resulting MsgBody (Bytes) here, it needs to be handled in our callback
		try {
		  request.response_body = yield session.send_and_read_async(request.msg, 0, request.cancellable);
		} catch (Error e) {
		  warning (@"Exception in network queue: $(e.message)");
		  ecb (0, e.message);
		}
		  
		var status = request.msg.status_code;
		if (status == Soup.Status.OK) {
		  if (request.cb != null) {
		    try {
		      request.cb (session, request);
		    } catch (Error e) {
		      warning (@"Error when executing message callback: $(e.message)");
		      ecb (0, e.message);
		    }
		  };
		} else if (request.cancellable.is_cancelled()) {
		  debug ("Message was cancelled. Ignoring callback invocation.");
		} else {
		  if (request.error_cb != null) {
		    try {
		      request.error_cb ((int32) status, request.msg.reason_phrase);
		    } catch (Error e) {
		      warning (@"Error when executing message error callback: $(e.message)");
		      ecb (0, e.message);
		    }
		  }
		}
	}

	public void on_error (int32 code, string message) {
		warning (message);
		app.toast (message);
	}

	public Json.Node parse_node (Tootle.Request req) throws Error {
		var parser = new Json.Parser ();
		parser.load_from_data ((string)req.response_body, -1);
		return parser.get_root ();
	}

	public Json.Object parse (Tootle.Request req) throws Error {
		return parse_node (req).get_object ();
	}

	public static void parse_array (Tootle.Request req, owned NodeCallback cb) throws Error {
	  var parser = new Json.Parser ();
	  parser.load_from_data ((string) req.response_body, -1);
	  parser.get_root ().get_array ().foreach_element ((array, i, node) => {
	      try {
		cb (node, req);
	      } catch (Error e) {
		warning (@"Error when parsing response Array: $(e.message)");
		req.error_cb (0, e.message);
	      }
	    });
	}

}
