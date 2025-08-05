// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UserForm extends StatefulWidget {
  const UserForm({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _UserFormState createState() => _UserFormState();
}

class _UserFormState extends State<UserForm> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _firstName = TextEditingController();
  final TextEditingController _lastName = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _gender = TextEditingController();
  final TextEditingController _birthday = TextEditingController();

  void _submitData() async {
    await FirebaseFirestore.instance.collection('users').add({
      'first_name': _firstName.text,
      'last_name': _lastName.text,
      'email': _email.text,
      'password': _password.text,
      'gender': _gender.text,
      'birthday': _birthday.text,
      'profile_picture': null, // can be added later
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("User added successfully")),
    );
    _formKey.currentState?.reset();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Add User')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(children: [
            TextFormField(controller: _firstName, decoration: InputDecoration(labelText: 'First Name')),
            TextFormField(controller: _lastName, decoration: InputDecoration(labelText: 'Last Name')),
            TextFormField(controller: _email, decoration: InputDecoration(labelText: 'Email')),
            TextFormField(controller: _password, decoration: InputDecoration(labelText: 'Password'), obscureText: true),
            TextFormField(controller: _gender, decoration: InputDecoration(labelText: 'Gender')),
            TextFormField(controller: _birthday, decoration: InputDecoration(labelText: 'Birthday')),
            SizedBox(height: 20),
            ElevatedButton(onPressed: _submitData, child: Text('Submit')),
          ]),
        ),
      ),
    );
  }
}
