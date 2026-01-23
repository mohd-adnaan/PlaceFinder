//
//  ConversationSection.swift
//  IndoorNavigationTACME
//
//  AI conversation UI section with voice input and chat history
//

import SwiftUI

struct ConversationSection: View {
    let conversationState: ConversationState
    let onSendMessage: (String) -> Void
    
    @State private var inputText: String = ""
    @State private var showHistory = true
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            conversationHeader
            
            // Voice input indicator
            if conversationState.isListening {
                listeningIndicator
            }
            
            // Current speech display
            if !conversationState.currentSpeechText.isEmpty {
                currentSpeechDisplay
            }
            
            // Chat history
            if showHistory && !conversationState.messages.isEmpty {
                chatHistory
            }
            
            // Text input
            textInputField
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Subviews
    
    private var conversationHeader: some View {
        HStack {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .foregroundColor(.blue)
            
            Text("AI Assistant")
                .font(.headline)
            
            Spacer()
            
            // Status indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(conversationState.isActive ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                
                Text(conversationState.isActive ? "Active" : "Inactive")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Toggle history button
            Button(action: { withAnimation { showHistory.toggle() } }) {
                Image(systemName: showHistory ? "chevron.up" : "chevron.down")
                    .foregroundColor(.gray)
            }
        }
    }
    
    private var listeningIndicator: some View {
        HStack(spacing: 12) {
            // Animated waveform
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue)
                        .frame(width: 4, height: CGFloat.random(in: 10...30))
                        .animation(
                            Animation.easeInOut(duration: 0.3)
                                .repeatForever()
                                .delay(Double(index) * 0.1),
                            value: conversationState.isListening
                        )
                }
            }
            .frame(height: 30)
            
            Text("Listening...")
                .font(.subheadline)
                .foregroundColor(.blue)
            
            Spacer()
            
            // Stop listening button
            Button(action: {
                // This would call stopListening
            }) {
                Image(systemName: "stop.circle.fill")
                    .font(.title2)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(10)
    }
    
    private var currentSpeechDisplay: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "waveform")
                .foregroundColor(.blue)
            
            Text(conversationState.currentSpeechText)
                .font(.subheadline)
                .foregroundColor(.primary)
                .italic()
            
            Spacer()
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
    }
    
    private var chatHistory: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(conversationState.messages) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 200)
            .onChange(of: conversationState.messages.count) { _ in
                if let lastMessage = conversationState.messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var textInputField: some View {
        HStack(spacing: 8) {
            TextField("Type a message...", text: $inputText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .submitLabel(.send)
                .onSubmit(sendMessage)
            
            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(inputText.isEmpty ? .gray : .blue)
            }
            .disabled(inputText.isEmpty)
        }
    }
    
    // MARK: - Actions
    
    private func sendMessage() {
        guard !inputText.isEmpty else { return }
        onSendMessage(inputText)
        inputText = ""
    }
}

// MARK: - Chat Bubble Component

struct ChatBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                // Message content
                Text(message.content)
                    .font(.subheadline)
                    .foregroundColor(message.isUser ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.isUser ? Color.blue : Color(.tertiarySystemBackground))
                    .cornerRadius(16)
                
                // Timestamp
                Text(formatTime(message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: message.isUser ? .trailing : .leading)
            
            if !message.isUser {
                Spacer()
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Preview

struct ConversationSection_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Active with messages
            ConversationSection(
                conversationState: ConversationState(
                    isActive: true,
                    isListening: false,
                    currentSpeechText: "",
                    messages: [
                        ChatMessage(id: UUID(), content: "How do I get to the elevator?", isUser: true, timestamp: Date().addingTimeInterval(-120)),
                        ChatMessage(id: UUID(), content: "From Room 101, go straight for 20 meters, then turn right. The elevator will be on your left.", isUser: false, timestamp: Date().addingTimeInterval(-60)),
                        ChatMessage(id: UUID(), content: "Thanks! What floor is the cafeteria on?", isUser: true, timestamp: Date())
                    ],
                    extractedIntent: nil,
                    lastError: nil
                ),
                onSendMessage: { _ in }
            )
            
            // Listening state
            ConversationSection(
                conversationState: ConversationState(
                    isActive: true,
                    isListening: true,
                    currentSpeechText: "How do I get to...",
                    messages: [],
                    extractedIntent: nil,
                    lastError: nil
                ),
                onSendMessage: { _ in }
            )
        }
        .padding()
    }
}
