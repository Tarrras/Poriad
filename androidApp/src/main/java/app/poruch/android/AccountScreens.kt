package app.poruch.android

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import app.poruch.shared.*

@Composable fun ProfileScreen(state: AppState, app: PoruchApp, login: () -> Unit, logout: () -> Unit) {
    Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
        PageHeader(stringResource(R.string.profile))
        Text(stringResource(if (state.userId == null) R.string.guest_title else R.string.account_title), style = MaterialTheme.typography.headlineSmall)
        Text(stringResource(if (state.userId == null) R.string.guest_description else R.string.account_description))
        if (state.passwordRecovery) {
            var password by remember { mutableStateOf("") }
            OutlinedTextField(password, { password = it }, label = { Text(stringResource(R.string.new_password)) }, visualTransformation = PasswordVisualTransformation())
            Button(onClick = { app.updatePassword(password) }, enabled = password.length >= 8 && !state.mutating) { Text(stringResource(R.string.update_password)) }
        }
        if (state.userId != null) {
            Text(stringResource(R.string.interests), style = MaterialTheme.typography.titleMedium)
            categories.chunked(2).forEach { pair -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { pair.forEach { category -> FilterChip(selected = category in state.interests, onClick = { app.toggleInterest(category) }, label = { Text(stringResource(categoryLabel(category))) }) } } }
            ReminderPreference(state)
        }
        Button(onClick = if (state.userId == null) login else logout) { Text(stringResource(if (state.userId == null) R.string.login else R.string.logout)) }
    }
}
@Composable fun AuthScreen(state: AppState, app: PoruchApp, back: () -> Unit) {
    var signup by rememberSaveable { mutableStateOf(false) }
    var email by rememberSaveable { mutableStateOf("") }
    var name by rememberSaveable { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    LaunchedEffect(state.userId) { if (state.userId != null && !state.passwordRecovery) back() }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        PageHeader(stringResource(if (signup) R.string.signup else R.string.login), back)
        Text(stringResource(R.string.auth_description))
        if (signup) OutlinedTextField(name, { name = it }, label = { Text(stringResource(R.string.name)) }, modifier = Modifier.fillMaxWidth(), singleLine = true)
        OutlinedTextField(email, { email = it }, label = { Text(stringResource(R.string.email)) }, modifier = Modifier.fillMaxWidth(), singleLine = true)
        OutlinedTextField(password, { password = it }, label = { Text(stringResource(R.string.password)) }, visualTransformation = PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth(), singleLine = true)
        Button(onClick = { if (signup) app.signUp(email.trim(), password, name.trim()) else app.signIn(email.trim(), password) }, enabled = !state.mutating && email.contains('@') && password.length >= 8 && (!signup || name.isNotBlank()), modifier = Modifier.fillMaxWidth()) { Text(stringResource(if (signup) R.string.signup else R.string.login)) }
        if (!signup) TextButton(onClick = { app.requestPasswordReset(email.trim()) }, enabled = email.contains('@') && !state.mutating) { Text(stringResource(R.string.forgot_password)) }
        TextButton(onClick = { signup = !signup }) { Text(stringResource(if (signup) R.string.have_account else R.string.new_account)) }
    }
}
