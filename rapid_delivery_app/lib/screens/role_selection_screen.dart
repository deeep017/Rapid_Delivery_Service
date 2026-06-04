import 'package:flutter/material.dart';
// ignore: unused_import
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import 'buyer/buyer_home_screen.dart';
import 'manager/manager_home_screen.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  bool _isLoading = false;
  String? _userName;
  String? _userEmail;
  String? _userRole;
  String? _warehouseId;
  String? _warehouseName;

  @override
  void initState() {
    super.initState();
    _checkExistingLogin();
  }

  Future<void> _checkExistingLogin() async {
    final user = await AuthService.getCurrentUser();
    if (user != null && user['email'] != null) {
      setState(() {
        _userName = user['name'];
        _userEmail = user['email'];
        _userRole = user['role'];
        _warehouseId = user['warehouseId'];
        _warehouseName = user['warehouseName'];
      });

      // Auto-navigate if already logged in
      if (_userRole == 'manager' &&
          _warehouseId != null &&
          _warehouseId!.isNotEmpty) {
        _navigateToManagerDashboard();
      }
    }
  }

  // =====================================================
  // BUYER LOGIN OPTIONS
  // =====================================================

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);

    try {
      final user = await AuthService.signInWithGoogle();
      if (user != null && mounted) {
        setState(() {
          _userName = user['name'];
          _userEmail = user['email'];
          _userRole = 'buyer';
        });
        _navigateToBuyerHome();
      } else if (mounted) {
        _showError('Google Sign-In cancelled or failed');
      }
    } catch (e) {
      if (mounted) _showError('Sign in failed: $e');
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _handleDemoLogin() async {
    setState(() => _isLoading = true);

    final user = await AuthService.signInAsDemo();
    setState(() {
      _userName = user['name'];
      _userEmail = user['email'];
      _userRole = 'buyer';
      _isLoading = false;
    });
    _navigateToBuyerHome();
  }

  Future<void> _handleManagerDemoLogin() async {
    setState(() => _isLoading = true);

    final manager = await AuthService.signInAsDemoManager();
    setState(() {
      _userName = manager.name;
      _userEmail = manager.email;
      _userRole = 'manager';
      _warehouseId = manager.warehouseId;
      _warehouseName = manager.warehouseName;
      _isLoading = false;
    });
    _navigateToManagerDashboard();
  }

  void _navigateToBuyerHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder:
            (ctx) => BuyerHomeScreen(
              userEmail: _userEmail ?? 'demo@rapid.com',
              userName: _userName ?? 'Demo User',
            ),
      ),
    );
  }

  // =====================================================
  // MANAGER LOGIN
  // =====================================================

  void _showManagerLoginDialog() {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    bool isLoggingIn = false;
    String? errorMessage;

    showDialog(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setDialogState) => AlertDialog(
                  title: const Row(
                    children: [
                      Icon(Icons.warehouse, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('Manager Login'),
                    ],
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (errorMessage != null)
                          Container(
                            padding: const EdgeInsets.all(8),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error,
                                  color: Colors.red,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    errorMessage!,
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        TextField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            hintText: 'manager.jaipur.central@rapid.com',
                            prefixIcon: Icon(Icons.email),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            prefixIcon: Icon(Icons.lock),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '📋 Demo Credentials:',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              _buildCredentialRow(
                                'Jaipur Central',
                                'manager.jaipur.central@rapid.com',
                                'jaipur123',
                              ),
                              _buildCredentialRow(
                                'LNMIIT',
                                'manager.lnmiit@rapid.com',
                                'lnmiit123',
                              ),
                              _buildCredentialRow(
                                'Mumbai',
                                'manager.mumbai@rapid.com',
                                'mumbai123',
                              ),
                              _buildCredentialRow(
                                'Bangalore',
                                'manager.bangalore@rapid.com',
                                'bangalore123',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed:
                          isLoggingIn
                              ? null
                              : () async {
                                setDialogState(() {
                                  isLoggingIn = true;
                                  errorMessage = null;
                                });

                                final manager =
                                    await AuthService.loginAsManager(
                                      email: emailController.text.trim(),
                                      password: passwordController.text,
                                    );

                                if (manager != null) {
                                  // ignore: use_build_context_synchronously
                                  Navigator.pop(ctx);
                                  setState(() {
                                    _userName = manager.name;
                                    _userEmail = manager.email;
                                    _userRole = 'manager';
                                    _warehouseId = manager.warehouseId;
                                    _warehouseName = manager.warehouseName;
                                  });
                                  _navigateToManagerDashboard();
                                } else {
                                  setDialogState(() {
                                    isLoggingIn = false;
                                    errorMessage = 'Invalid email or password';
                                  });
                                }
                              },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                      ),
                      child:
                          isLoggingIn
                              ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Text(
                                'Login',
                                style: TextStyle(color: Colors.white),
                              ),
                    ),
                  ],
                ),
          ),
    );
  }

  Widget _buildCredentialRow(String warehouse, String email, String password) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        '$warehouse: $password',
        style: TextStyle(fontSize: 11, color: Colors.grey[700]),
      ),
    );
  }

  void _navigateToManagerDashboard() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder:
            (ctx) => ManagerHomeScreen(
              userEmail: _userEmail ?? '',
              userName: _userName ?? 'Manager',
              warehouseId: _warehouseId,
              warehouseName: _warehouseName,
            ),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0C831F), Color(0xFF1E5631)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 32),

                        // Logo & Title
                        const Icon(
                          Icons.rocket_launch,
                          size: 80,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Rapid Delivery',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Groceries delivered in 10 minutes',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),

                        const SizedBox(height: 48),

                        // Role Selection
                        const Text(
                          'Choose your role:',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Buyer Card
                        _buildRoleCard(
                          icon: Icons.shopping_cart,
                          title: 'I\'m a Buyer',
                          subtitle: 'Browse products & place orders',
                          color: Colors.blue,
                          buttons: [
                            _ActionButton(
                              label: 'Sign in with Google',
                              icon: Icons.g_mobiledata,
                              onTap: _isLoading ? null : _handleGoogleSignIn,
                              isPrimary: true,
                            ),
                            _ActionButton(
                              label: 'Demo Mode',
                              icon: Icons.play_arrow,
                              onTap: _isLoading ? null : _handleDemoLogin,
                              isPrimary: false,
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Manager Card
                        _buildRoleCard(
                          icon: Icons.warehouse,
                          title: 'I\'m a Warehouse Manager',
                          subtitle: 'Manage inventory & view orders',
                          color: Colors.orange,
                          buttons: [
                            _ActionButton(
                              label: 'Manager Login',
                              icon: Icons.login,
                              onTap: _showManagerLoginDialog,
                              isPrimary: true,
                            ),
                            _ActionButton(
                              label: 'Demo Mode (LNMIIT)',
                              icon: Icons.play_arrow,
                              onTap:
                                  _isLoading ? null : _handleManagerDemoLogin,
                              isPrimary: false,
                            ),
                          ],
                        ),

                        const SizedBox(height: 48),

                        // Footer
                        Text(
                          'CAP Theorem Demo • Distributed Systems Project',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required List<_ActionButton> buttons,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 28, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...buttons.map(
            (btn) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child:
                    btn.isPrimary
                        ? ElevatedButton.icon(
                          onPressed: btn.onTap,
                          icon: Icon(btn.icon, size: 20),
                          label: Text(btn.label),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: color,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        )
                        : OutlinedButton.icon(
                          onPressed: btn.onTap,
                          icon: Icon(btn.icon, size: 20, color: color),
                          label: Text(
                            btn.label,
                            style: TextStyle(color: color),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: color),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isPrimary;

  _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.isPrimary,
  });
}
