package com.megablok10.app.ui.screens

import androidx.lifecycle.ViewModel
import com.megablok10.app.announce.Announcement
import com.megablok10.app.announce.AnnouncementStore
import kotlinx.coroutines.flow.StateFlow

/** Объявления мастера: окно с непрочитанными (AnnouncementDialogHost) и список в Настройках. */
class AnnouncementsViewModel(private val store: AnnouncementStore) : ViewModel() {
    val items: StateFlow<List<Announcement>> = store.items

    fun markAllRead() = store.markAllRead()
}
