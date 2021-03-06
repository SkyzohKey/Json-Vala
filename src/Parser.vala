namespace Json {
	public errordomain ParserError {
		NULL,
		INVALID,
		EOF
	}
	
	internal static bool is_valid_string (string str) {
		if (str[0] == '"')
			return false;
		var pos = 1;
		while (pos < str.length) {
			if (str[pos] == '"' && str[pos - 1] != '\\')
				return false;
			pos++;
		}
		return true;
	}
	
	public class Parser : GLib.Object {
		public Json.Node root { get; private set; }
		
		public bool decode_unicode { get; set; }
		public bool unescape { get; set; }
		
		construct {
			unescape = true;
			decode_unicode = true;
		}
		
		public void load_from_path (string path, Encoding encoding = Encoding.utf8) throws GLib.Error {
			var reader = new StreamReader (File.new_for_path (path).read(), encoding);
			load (reader);
		}
		
		public async void load_from_path_async (string path, Encoding encoding = Encoding.utf8) throws GLib.Error {
			ThreadFunc<void*> run = () => {
				load_from_path (path, encoding);
				Idle.add (load_from_path_async.callback);
				return null;
			};
			Thread.create<void*>(run, false);
			yield;
		}
		
		public void load_from_data (string data) throws GLib.Error {
			var reader = new StringReader (data);
			load (reader);
		}
		
		public async void load_from_data_async (string data) throws GLib.Error {
			ThreadFunc<void*> run = () => {
				load_from_data (data);
				Idle.add (load_from_data_async.callback);
				return null;
			};
			Thread.create<void*>(run, false);
			yield;
		}
		
		public void load_from_uri (string uri, Encoding encoding = Encoding.utf8) throws GLib.Error {
			uint8[] data = new uint8[30];
			var file = File.new_for_uri (uri);
			var count = file.read().read (data);
			data.resize ((int)count);
			var reader = new StreamReader (file.read(), encoding);
			load (reader);
		}
		
		public async void load_from_uri_async (string uri, Encoding encoding = Encoding.utf8) throws GLib.Error {
			ThreadFunc<void*> run = () => {
				load_from_uri (uri, encoding);
				Idle.add (load_from_uri_async.callback);
				return null;
			};
			Thread.create<void*>(run, false);
			yield;
		}
		
		public void load (Reader reader) throws GLib.Error {
			var dt = new DateTime.now_local();
			parsing_start();
			while (reader.peek().isspace())
				reader.read();
			if (reader.peek() == '[')
				root = new Json.Node (read_array (reader));
			else if (reader.peek() == '{')
				root = new Json.Node (read_object (reader));
			else
				throw new ParserError.INVALID ("invalid JSON data %u".printf (reader.peek()));
			var ts = new DateTime.now_local().difference (dt);
			parsing_end (ts);
		}
		
		public async void load_async (Reader reader) throws GLib.Error {
			ThreadFunc<void*> run = () => {
				load (reader);
				Idle.add (load_async.callback);
				return null;
			};
			Thread.create<void*>(run, false);
			yield;
		}
		
		public signal void parsing_start();
		public signal void parsing_end (TimeSpan duration);
		
		Json.Object read_object (Reader reader) throws GLib.Error {
			if (reader.peek() != '{')
				throw new ParserError.INVALID ("invalid character. '{' expected but '%s' was found.".printf (reader.peek().to_string()));
			reader.read();
			while (reader.peek().isspace())
				reader.read();
			var object = new Json.Object();
			if (reader.peek() == '}') {
				reader.read();
				return object;
			}
			while (reader.peek() != 0) {
				while (reader.peek().isspace())
					reader.read();
				string key = read_string (reader);
				while (reader.peek().isspace())
					reader.read();
				if (reader.peek() != ':')
					throw new ParserError.INVALID ("invalid character. ':' expected but '%s' was found.".printf (reader.peek().to_string()));
				reader.read();
				while (reader.peek().isspace())
					reader.read();
				if (reader.peek() == '[')
					object.set_array_member (key, read_array (reader));
				else if (reader.peek() == '{')
					object.set_object_member (key, read_object (reader));
				else if (reader.peek() == '"')
					object.set_string_member (key, read_string (reader));
				else {
					StringBuilder sb = new StringBuilder();
					while (reader.peek() != 0 && reader.peek() != ',' && reader.peek() != '}')
						sb.append_unichar (reader.read());
					string str = sb.str.strip();
					if (str.length == 0)	
						throw new ParserError.NULL ("value length is 0.");
					int64 num; double d;
					if (int64.try_parse (str, out num))
						object.set_int_member (key, num);
					else if (double.try_parse (str, out d))
						object.set_double_member (key, d);
					else if (str == "true" || str == "false")
						object.set_boolean_member (key, str == "true");
					else if (str == "null")
						object.set_null_member (key);
					else throw new ParserError.INVALID ("invalid object member : %s\n".printf (str));
				}
				while (reader.peek().isspace())
					reader.read();
				if (reader.peek() == '}')
					break;
				if (reader.peek() != ',')
					throw new ParserError.INVALID ("invalid end of object member : %s\n".printf (reader.peek().to_string()));
				reader.read();
			}
			if (reader.peek() == 0)
				throw new ParserError.EOF ("end of file.");
			reader.read();
			return object;
		}
		
		Json.Array read_array (Reader reader) throws GLib.Error {
			if (reader.peek() != '[')
				throw new ParserError.INVALID ("invalid character. '[' expected but '%s' was found.".printf (reader.peek().to_string()));
			reader.read();
			while (reader.peek().isspace())
				reader.read();
			var array = new Json.Array();
			if (reader.peek() == ']') {
				reader.read();
				return array;
			}
			while (reader.peek() != 0) {
				while (reader.peek().isspace())
					reader.read();
				if (reader.peek() == '[')
					array.add_array_element (read_array (reader));
				else if (reader.peek() == '{')
					array.add_object_element (read_object (reader));
				else if (reader.peek() == '"')
					array.add_string_element (read_string (reader));
				else {
					StringBuilder sb = new StringBuilder();
					while (reader.peek() != 0 && reader.peek() != ',' && reader.peek() != ']')
						sb.append_unichar (reader.read());
					string str = sb.str.strip();
					if (str.length == 0)	
						throw new ParserError.NULL ("value length is 0.");
					int64 num; double d;
					if (int64.try_parse (str, out num))
						array.add_int_element (num);
					else if (double.try_parse (str, out d))
						array.add_double_element (d);
					else if (str == "true" || str == "false")
						array.add_boolean_element (str == "true");
					else if (str == "null")
						array.add_null_element();
					else throw new ParserError.INVALID ("invalid array element : %s\n".printf (str));
				}
				while (reader.peek().isspace())
					reader.read();
				if (reader.peek() == ']')
					break;
				if (reader.peek() != ',')
					throw new ParserError.INVALID ("invalid end of array element : %s\n".printf (reader.peek().to_string()));
				reader.read();
			}
			if (reader.peek() == 0)
				throw new ParserError.EOF ("end of file.");
			reader.read();
			return array;
		}
		
		string read_string (Reader reader) throws GLib.Error {
			if (reader.peek() != '"')
				throw new ParserError.INVALID ("invalid character. '\"' expected but '%s' was found.".printf (reader.peek().to_string()));
			StringBuilder sb = new StringBuilder();
			reader.read();
			while (reader.peek() != 0) {
				if (reader.peek() == '"') {
					reader.read();
					if (unescape)
						return sb.str.compress();
					return sb.str;
				}
				if (reader.peek() == '\r' || reader.peek() == '\n')
					throw new ParserError.INVALID ("string is truncated");
				if (reader.peek() == '\\') {
					reader.read();
					unichar u = reader.read();
					if (u == 'u' && decode_unicode) {
						unichar a = reader.read();
						if (a == 0)
							throw new ParserError.EOF ("end of file");
						unichar b = reader.read();
						if (b == 0)
							throw new ParserError.EOF ("end of file");
						unichar c = reader.read();
						if (c == 0)
							throw new ParserError.EOF ("end of file");
						unichar d = reader.read();
						if (d == 0)
							throw new ParserError.EOF ("end of file");
						string s = "0x%s%s%s%s".printf (a.to_string(), b.to_string(), c.to_string(), d.to_string());
						int64 i = 0;
						if (!int64.try_parse (s, out i))
							throw new ParserError.INVALID ("invalid unicode character");
						sb.append_unichar ((unichar)i);
					}
					else {
						sb.append_unichar ('\\');
						sb.append_unichar (u);
					}
					continue;
				}
				sb.append_unichar (reader.read());
			}
			if (reader.peek() == 0)
				throw new ParserError.EOF ("end of file");
			if (unescape)
				return sb.str.compress();
			return sb.str;
		}
	}
}
