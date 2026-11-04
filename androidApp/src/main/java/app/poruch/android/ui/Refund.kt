package app.poruch.android.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import app.poruch.android.R
import app.poruch.domain.RefundPolicy

/** Правила повернення онлайн-події людськими словами; онлайн-подія без правил (стара) — null. */
@Composable
fun refundText(policy: RefundPolicy?): String? = policy?.let {
    val rule = when (it) {
        RefundPolicy.BEFORE_48H -> R.string.refund_before_48h
        RefundPolicy.BEFORE_24H -> R.string.refund_before_24h
        RefundPolicy.CANCEL_ONLY -> R.string.refund_cancel_only
    }
    stringResource(rule) + " " + stringResource(R.string.refund_organizer_cancels)
}
