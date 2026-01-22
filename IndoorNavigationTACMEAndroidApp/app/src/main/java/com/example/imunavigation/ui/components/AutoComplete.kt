// Autocomplete.kt - Simplified version to prevent crashes
package com.example.imunavigation.ui.components

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.unit.dp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun Autocomplete(
    value: String,
    onValueChange: (String) -> Unit,
    poiNames: List<String>,
    label: String,
    modifier: Modifier = Modifier
) {
    var expanded by remember { mutableStateOf(false) }
    var filteredNames by remember { mutableStateOf<List<String>>(emptyList()) }
    val focusManager = LocalFocusManager.current


    LaunchedEffect(value, poiNames) {
        try {
            val validPOIs = poiNames.filterNot { it.isBlank() || it == "null" }
            filteredNames = if (value.isEmpty()) {
                validPOIs.take(8) // Smaller list to reduce crash risk
            } else {
                validPOIs.filter { name ->
                    name.contains(value, ignoreCase = true)
                }.take(8)
            }
        } catch (e: Exception) {
            filteredNames = emptyList()
        }
    }

    Column(modifier = modifier) {
        ExposedDropdownMenuBox(
            expanded = expanded,
            onExpandedChange = {
                try {
                    expanded = it && filteredNames.isNotEmpty()
                } catch (e: Exception) {
                    expanded = false
                }
            }
        ) {
            OutlinedTextField(
                value = value,
                onValueChange = { newValue ->
                    try {
                        onValueChange(newValue)
                        expanded = true
                    } catch (e: Exception) {
                        expanded = false
                    }
                },
                label = { Text(label) },
                modifier = Modifier
                    .menuAnchor()
                    .fillMaxWidth()
                    .onFocusChanged { focusState ->
                        try {
                            if (focusState.isFocused && filteredNames.isNotEmpty()) {
                                expanded = true
                            }
                        } catch (e: Exception) {
                            expanded = false
                        }
                    },
                singleLine = true,
                trailingIcon = {
                    Row {
                        if (value.isNotEmpty()) {
                            IconButton(
                                onClick = {
                                    try {
                                        onValueChange("")
                                        expanded = false
                                    } catch (e: Exception) {
                                        // Ignore errors in cleanup
                                    }
                                }
                            ) {
                                Icon(Icons.Default.Clear, "Clear")
                            }
                        }
                        ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded)
                    }
                }
            )

            // Basic DropdownMenuItem without scrolling
            if (expanded && filteredNames.isNotEmpty()) {
                ExposedDropdownMenu(
                    expanded = expanded,
                    onDismissRequest = { expanded = false }
                ) {

                    filteredNames.take(5).forEach { name -> // Limit to 5 items max
                        DropdownMenuItem(
                            text = { Text(name) },
                            onClick = {
                                try {
                                    onValueChange(name)
                                    expanded = false
                                    focusManager.clearFocus()
                                } catch (e: Exception) {
                                    expanded = false
                                }
                            }
                        )
                    }
                }
            }
        }
    }
}