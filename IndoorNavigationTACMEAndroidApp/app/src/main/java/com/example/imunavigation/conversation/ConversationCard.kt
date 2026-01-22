package com.example.imunavigation.conversation

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.imunavigation.language.LanguageManager // NEW
import kotlinx.coroutines.launch

/**
 * Conversation card with bilingual support
 */
@Composable
fun ConversationCard(
    conversationState: ConversationManager.ConversationState,
    onStartConversation: () -> Unit,
    onStopConversation: () -> Unit,
    onStartListening: () -> Unit,
    onStopListening: () -> Unit,
    onSendMessage: (String) -> Unit,
    languageManager: LanguageManager // NEW - add this parameter
) {
    var textInput by remember { mutableStateOf("") }
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()

    // NEW: Get localized strings
    val titleText = "TACME" // Keep brand name
    val placeholderText = if (languageManager.isFrench()) {
        "Demander de l'aide pour la localisation..."
    } else {
        "Request location assistance..."
    }
    val sendButtonDesc = languageManager.getString("Send")
    val processingText = languageManager.getString("Processing")
    val descriptionText = if (languageManager.isFrench()) {
        "Activez le mode conversation pour poser des questions sur la navigation, les emplacements et obtenir des directions en langage naturel."
    } else {
        "Enable conversation mode to ask questions about navigation, locations, and get directions through natural language."
    }

    // Auto-scroll to bottom when new messages arrive
    LaunchedEffect(conversationState.conversationHistory.size) {
        if (conversationState.conversationHistory.isNotEmpty()) {
            scope.launch {
                listState.animateScrollToItem(conversationState.conversationHistory.size - 1)
            }
        }
    }

    Card(
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 4.dp),
        colors = CardDefaults.cardColors(
            containerColor = if (conversationState.isActive)
                MaterialTheme.colorScheme.primaryContainer
            else MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Column(
            modifier = Modifier.padding(16.dp)
        ) {
            // Header with conversation toggle
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = titleText,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )

                Switch(
                    checked = conversationState.isActive,
                    onCheckedChange = { isActive ->
                        if (isActive) {
                            onStartConversation()
                        } else {
                            onStopConversation()
                        }
                    }
                )
            }

            if (conversationState.isActive) {
                Spacer(modifier = Modifier.height(16.dp))

                // Chat history
                if (conversationState.conversationHistory.isNotEmpty()) {
                    LazyColumn(
                        state = listState,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(300.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        items(conversationState.conversationHistory) { message ->
                            ChatBubble(
                                message = message.message,
                                isUser = message.isUser
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(16.dp))
                }

                // Input section
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Text input
                    OutlinedTextField(
                        value = textInput,
                        onValueChange = { textInput = it },
                        modifier = Modifier.weight(1f),
                        placeholder = { Text(placeholderText) }, // NEW: Localized
                        enabled = !conversationState.isProcessing,
                        singleLine = true
                    )

                    // Send button
                    Button(
                        onClick = {
                            if (textInput.isNotBlank()) {
                                onSendMessage(textInput)
                                textInput = ""
                            }
                        },
                        enabled = textInput.isNotBlank() && !conversationState.isProcessing,
                        modifier = Modifier.size(48.dp),
                        contentPadding = PaddingValues(0.dp)
                    ) {
                        Icon(
                            Icons.Default.Send,
                            contentDescription = sendButtonDesc // NEW: Localized
                        )
                    }
                }

                // Processing indicator
                if (conversationState.isProcessing) {
                    Spacer(modifier = Modifier.height(16.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.Center,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        CircularProgressIndicator(modifier = Modifier.size(16.dp))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("$processingText...") // NEW: Localized
                    }
                }

                // Error message
                conversationState.errorMessage?.let { error ->
                    Spacer(modifier = Modifier.height(8.dp))
                    Card(
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.errorContainer
                        )
                    ) {
                        Text(
                            text = error,
                            modifier = Modifier.padding(12.dp),
                            color = MaterialTheme.colorScheme.onErrorContainer,
                            style = MaterialTheme.typography.bodySmall
                        )
                    }
                }
            } else {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = descriptionText, // NEW: Localized
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

/**
 * Individual chat bubble for messages
 */
@Composable
private fun ChatBubble(
    message: String,
    isUser: Boolean
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start
    ) {
        Card(
            modifier = Modifier.widthIn(max = 280.dp),
            shape = RoundedCornerShape(
                topStart = 16.dp,
                topEnd = 16.dp,
                bottomStart = if (isUser) 16.dp else 4.dp,
                bottomEnd = if (isUser) 4.dp else 16.dp
            ),
            colors = CardDefaults.cardColors(
                containerColor = if (isUser) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.secondaryContainer
                }
            )
        ) {
            Text(
                text = message,
                modifier = Modifier.padding(12.dp),
                color = if (isUser) {
                    MaterialTheme.colorScheme.onPrimary
                } else {
                    MaterialTheme.colorScheme.onSecondaryContainer
                },
                style = MaterialTheme.typography.bodyMedium
            )
        }
    }
}