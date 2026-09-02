import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../main.dart';
import '../services/technician_session_service.dart';
import '../widgets_root_back_scope.dart';
import '../utils/app_colors.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _employeeIdController = TextEditingController();
  final _pinController = TextEditingController();

  bool _isLoading = false;
  bool _hidePin = true;
  String? _errorMessage;

  @override
  void dispose() {
    _employeeIdController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final employeeId = _employeeIdController.text.trim();
    final pin = _pinController.text.trim();

    if (employeeId.isEmpty || pin.isEmpty) {
      setState(() => _errorMessage = 'Please enter Employee ID and PIN.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Firebase is used for backend authentication. The employee never sees
      // an email/password field.
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }

      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('employeeId', isEqualTo: employeeId)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        _showError('Employee ID not found.');
        return;
      }

      final doc = query.docs.first;
      final data = doc.data();
      final storedPin = data['pin']?.toString().trim() ?? '';

      if (storedPin.isEmpty || storedPin != pin) {
        _showError('Incorrect PIN.');
        return;
      }

      final role = data['role']?.toString().toLowerCase().trim();
      if (role != 'admin' && role != 'technician' && role != 'water_plant_manager') {
        _showError('This employee account has no valid role.');
        return;
      }

      await TechnicianSessionService().saveUserId(doc.id);

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      _showError('Firebase login failed: ${e.message ?? e.code}');
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        _showError(
          'Firebase denied access to the users collection. Check Firestore rules.',
        );
      } else {
        _showError('Login failed: ${e.message ?? e.code}');
      }
    } catch (e) {
      _showError('Login failed: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return RootBackScope(
      child: Scaffold(
        body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  Image.asset(
                    'assets/logo.png',
                    height: 76,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'TechAllocate',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Employee Login',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.mutedDark,
                    ),
                  ),
                  const SizedBox(height: 30),
                  TextField(
                    controller: _employeeIdController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Employee ID',
                      hintText: 'Enter employee ID',
                      prefixIcon: Icon(Icons.badge_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _pinController,
                    obscureText: _hidePin,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _isLoading ? null : _login(),
                    decoration: InputDecoration(
                      labelText: 'PIN',
                      hintText: 'Enter PIN',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _hidePin = !_hidePin),
                        icon: Icon(
                          _hidePin ? Icons.visibility : Icons.visibility_off,
                        ),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_errorMessage != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _login,
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Log In'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}
