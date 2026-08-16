package dev.mulev.flureadium.fragments

import android.os.Bundle
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import dev.mulev.flureadium.databinding.FragmentReaderBinding
import dev.mulev.flureadium.viewLifecycle
import org.readium.r2.navigator.VisualNavigator

private const val TAG = "VisualReaderFragment"

abstract class VisualReaderFragment : BaseReaderFragment() {
    private var binding: FragmentReaderBinding by viewLifecycle()

    /**
     * The Readium navigator this fragment currently hosts, or null between a
     * pause that removed it and the resume that builds the next one.
     */
    val visualNavigator: VisualNavigator? get() = navigator as? VisualNavigator

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        Log.d(TAG, "::onCreateView")
        binding = FragmentReaderBinding.inflate(inflater, container, false)

        return binding.root
    }
}
