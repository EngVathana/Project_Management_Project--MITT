import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../app/widgets.dart';
import 'session.dart';

String? validatePhone(String? input) {
  final value = input?.trim() ?? '';
  final count = value.replaceAll(RegExp(r'\D'), '').length;
  return !RegExp(r'^\+?[\d() .-]+$').hasMatch(value) || count < 7 || count > 15
      ? 'Enter a valid phone number.'
      : null;
}

String? validatePassword(String? value) =>
    value == null || value.length < 8 || utf8.encode(value).length > 72
    ? 'Use 8 characters or more, up to 72 UTF-8 bytes.'
    : null;

enum AuthMode { login, create, change }

class AccountView extends StatefulWidget {
  const AccountView({super.key, required this.session});
  final Session session;
  @override
  State<AccountView> createState() => _AccountViewState();
}

class _AccountViewState extends State<AccountView> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final phone = TextEditingController();
  final first = TextEditingController();
  final next = TextEditingController();
  final confirmation = TextEditingController();
  AuthMode mode = AuthMode.login;
  String? error;
  bool busy = false;

  @override
  void dispose() {
    for (final controller in [name, phone, first, next, confirmation]) {
      controller.dispose();
    }
    super.dispose();
  }

  void select(AuthMode value) {
    first.clear();
    next.clear();
    confirmation.clear();
    setState(() {
      mode = value;
      error = null;
    });
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    final session = widget.session;
    try {
      switch (mode) {
        case AuthMode.login:
          await session.login(phone.text, first.text);
        case AuthMode.create:
          await session.repository.register(
            name.text,
            phone.text,
            first.text,
            confirmation.text,
            portal: session.portal,
          );
          if (mounted) {
            select(AuthMode.login);
            notify(context, 'Account created. Sign in to continue.');
          }
        case AuthMode.change:
          await session.repository.changePassword(
            phone.text,
            first.text,
            next.text,
            confirmation.text,
          );
          if (mounted) {
            select(AuthMode.login);
            notify(
              context,
              'Password changed. Sign in with your new password.',
            );
          }
      }
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } on Exception {
      if (mounted) setState(() => error = 'Could not complete account access.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.session.user;
    if (user != null) {
      return PageList(
        width: 430,
        children: [
          const SectionTitle('Account'),
          Text(user['name'] as String),
          Text(user['phone'] as String),
          TextButton(
            onPressed: () => perform(context, widget.session.logout),
            child: const Text('Sign out'),
          ),
        ],
      );
    }
    final title = switch (mode) {
      AuthMode.login => 'Welcome back',
      AuthMode.create => 'Create your account',
      AuthMode.change => 'Change password',
    };
    return PageList(
      width: 432,
      children: [
        SizedBox(
          height: 144,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Positioned(
                left: 22,
                top: 24,
                child: Icon(Icons.pets, color: Color(0xffdfd4eb)),
              ),
              const Positioned(
                right: 25,
                bottom: 24,
                child: Icon(Icons.pets, color: Color(0xffdfd4eb)),
              ),
              Image.asset('assets/mitt.png', width: 150),
            ],
          ),
        ),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionTitle(title),
                  if (mode == AuthMode.create)
                    InputField(
                      label: 'Full name',
                      controller: name,
                      validator: (value) =>
                          (value?.trim().length ?? 0) < 1 ||
                              value!.trim().length > 100
                          ? 'Enter up to 100 characters.'
                          : null,
                    ),
                  InputField(
                    label: 'Phone number',
                    controller: phone,
                    keyboard: TextInputType.phone,
                    validator: validatePhone,
                  ),
                  SecretField(
                    label: mode == AuthMode.change
                        ? 'Old password'
                        : 'Password',
                    controller: first,
                    validator: validatePassword,
                  ),
                  if (mode == AuthMode.change)
                    SecretField(
                      label: 'New password',
                      controller: next,
                      validator: (value) =>
                          validatePassword(value) ??
                          (value == first.text
                              ? 'Choose a different password.'
                              : null),
                    ),
                  if (mode != AuthMode.login)
                    SecretField(
                      label: 'Confirm password',
                      controller: confirmation,
                      validator: (value) =>
                          value !=
                              (mode == AuthMode.change ? next.text : first.text)
                          ? 'The passwords do not match.'
                          : validatePassword(value),
                    ),
                  if (mode == AuthMode.login)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: busy ? null : () => select(AuthMode.change),
                        child: const Text('Forgot password?'),
                      ),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    child: Text(
                      busy
                          ? 'Please wait…'
                          : switch (mode) {
                              AuthMode.login => 'Log in',
                              AuthMode.create => 'Create account',
                              AuthMode.change => 'Change password',
                            },
                    ),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => select(
                            mode == AuthMode.login
                                ? AuthMode.create
                                : AuthMode.login,
                          ),
                    child: Text(
                      mode == AuthMode.login
                          ? (widget.session.portal
                                ? 'Register as a store owner'
                                : 'New to MITT? Sign up')
                          : 'Back to sign in',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class SecretField extends StatefulWidget {
  const SecretField({
    super.key,
    required this.label,
    required this.controller,
    required this.validator,
  });
  final String label;
  final TextEditingController controller;
  final FormFieldValidator<String> validator;
  @override
  State<SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<SecretField> {
  bool hidden = true;
  @override
  Widget build(BuildContext context) => InputField(
    label: widget.label,
    controller: widget.controller,
    validator: widget.validator,
    obscure: hidden,
    suffix: IconButton(
      tooltip: hidden ? 'Show password' : 'Hide password',
      onPressed: () => setState(() => hidden = !hidden),
      icon: Icon(
        hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      ),
    ),
  );
}
