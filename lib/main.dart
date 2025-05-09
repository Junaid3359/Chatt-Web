import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';



void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chat App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.teal),
      home: AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (ctx, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(body: Center(child: CircularProgressIndicator()));
        } else if (snapshot.hasData) {
          return HomeScreen();
        } else {
          return AuthScreen();
        }
      },
    );
  }
}

class AuthScreen extends StatefulWidget {
  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLogin = true;
  String _email = '', _password = '', _name = '';
  bool _isLoading = false;

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    setState(() => _isLoading = true);
    try {
      final auth = FirebaseAuth.instance;
      UserCredential userCred;
      if (_isLogin) {
        userCred = await auth.signInWithEmailAndPassword(email: _email, password: _password);
      } else {
        userCred = await auth.createUserWithEmailAndPassword(email: _email, password: _password);
        await userCred.user!.updateDisplayName(_name);
        await FirebaseFirestore.instance.collection('users').doc(userCred.user!.uid).set({
          'uid': userCred.user!.uid,
          'email': _email,
          'name': _name,
        });
      }

      // FCM token
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userCred.user!.uid)
            .update({'fcmToken': fcmToken});
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.teal.shade50,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_isLogin ? 'Login' : 'Sign Up', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  SizedBox(height: 20),
                  if (!_isLogin)
                    TextFormField(
                      decoration: InputDecoration(labelText: 'Name'),
                      validator: (val) => val!.isEmpty ? 'Enter name' : null,
                      onSaved: (val) => _name = val!,
                    ),
                  TextFormField(
                    decoration: InputDecoration(labelText: 'Email'),
                    validator: (val) => val!.contains('@') ? null : 'Enter valid email',
                    onSaved: (val) => _email = val!,
                  ),
                  TextFormField(
                    decoration: InputDecoration(labelText: 'Password'),
                    obscureText: true,
                    validator: (val) => val!.length < 6 ? 'Min 6 chars' : null,
                    onSaved: (val) => _password = val!,
                  ),
                  SizedBox(height: 20),
                  _isLoading
                      ? CircularProgressIndicator()
                      : ElevatedButton(
                          child: Text(_isLogin ? 'Login' : 'Sign Up'),
                          onPressed: _submit,
                        ),
                  TextButton(
                    onPressed: () => setState(() => _isLogin = !_isLogin),
                    child: Text(_isLogin ? 'Create account' : 'Already have account? Login'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  final user = FirebaseAuth.instance.currentUser;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Users'),
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () async => await FirebaseAuth.instance.signOut(),
          )
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator());
          final users = snap.data!.docs.where((doc) => doc['uid'] != user!.uid).toList();
          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (ctx, i) {
              final u = users[i];
              return ListTile(
                leading: CircleAvatar(child: Text(u['name'][0])),
                title: Text(u['name']),
                subtitle: Text(u['email']),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ChatScreen(receiverId: u['uid'], receiverName: u['name']),
                )),
              );
            },
          );
        },
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String receiverId, receiverName;
  ChatScreen({required this.receiverId, required this.receiverName});
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final user = FirebaseAuth.instance.currentUser;
  final ImagePicker _picker = ImagePicker();

  Future<void> _sendImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      // In a real application, you would upload this image to Firebase Storage
      // and then send a message containing the download URL.
      print('Image selected: ${image.path}');
      await FirebaseFirestore.instance.collection('chats').add({
        'type': 'image', // Indicate the message type
        'imageUrl': 'URL_OF_UPLOADED_IMAGE', // Replace with the actual URL
        'senderId': user!.uid,
        'receiverId': widget.receiverId,
        'timestamp': Timestamp.now(),
      });
    }
  }

  Future<void> _sendLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Location permissions are denied')));
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Location permissions are permanently denied, we cannot request permissions.')));
      return;
    }

    try {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      print('Latitude: ${position.latitude}, Longitude: ${position.longitude}');
      await FirebaseFirestore.instance.collection('chats').add({
        'type': 'location', // Indicate the message type
        'latitude': position.latitude,
        'longitude': position.longitude,
        'senderId': user!.uid,
        'receiverId': widget.receiverId,
        'timestamp': Timestamp.now(),
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error getting location: $e')));
    }
  }

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();

    await FirebaseFirestore.instance.collection('chats').add({
      'text': text,
      'senderId': user!.uid,
      'receiverId': widget.receiverId,
      'timestamp': Timestamp.now(),
    });

    // Optional: Trigger FCM manually via Firebase Functions or a server
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.receiverName)),
      body: Column(
        children: [
          Expanded(
  child: StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance
        .collection('chats')
        .orderBy('timestamp', descending: true)
        .where('senderId', whereIn: [user!.uid, widget.receiverId])
        .snapshots(),
    builder: (ctx, snap) {
      if (!snap.hasData) return Center(child: CircularProgressIndicator());
      final msgs = snap.data!.docs.where((doc) =>
          (doc['senderId'] == user!.uid && doc['receiverId'] == widget.receiverId) ||
          (doc['senderId'] == widget.receiverId && doc['receiverId'] == user!.uid)).toList();
      return ListView.builder(
        reverse: true,
        itemCount: msgs.length,
        itemBuilder: (ctx, i) {
          final m = msgs[i];
          final isMe = m['senderId'] == user!.uid;
          Widget messageContent;

          final messageData = m.data() as Map<String, dynamic>?; // Cast to Map or null

          if (messageData != null && messageData.containsKey('type') && messageData['type'] == 'image' && messageData.containsKey('imageUrl')) {
            messageContent = SizedBox(
              width: 200, // Adjust as needed
              height: 200, // Adjust as needed
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  messageData['imageUrl'],
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Center(child: Text('Failed to load image'));
                  },
                ),
              ),
            );
          } else if (messageData != null && messageData.containsKey('type') && messageData['type'] == 'location' && messageData.containsKey('latitude') &&
              messageData.containsKey('longitude')) {
            messageContent = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('[Location Sent:]', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('Latitude: ${messageData['latitude']?.toStringAsFixed(6)}'),
                Text('Longitude: ${messageData['longitude']?.toStringAsFixed(6)}'),
                // You could add a map preview here using a package like google_maps_flutter
                // For a simple text-based solution, the above is sufficient.
              ],
            );
          } else {
            messageContent = Text(m['text'] as String? ?? ''); // Handle potential null text
          }

          return Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? Colors.teal.shade200 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(12),
              ),
              child: messageContent,
            ),
          );
        },
      );
    },
  ),
),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.image, color: Colors.teal),
                  onPressed: _sendImage,
                ),
                IconButton(
                  icon: Icon(Icons.location_on, color: Colors.teal),
                  onPressed: _sendLocation,
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Enter message',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send, color: Colors.teal),
                  onPressed: _sendMessage,
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}



