import SwiftUI
import Highlightr

struct HighlightrCodeEditor: NSViewRepresentable {
    @Binding var text: String
    let highlightr = Highlightr()!
    
    init(text: Binding<String>) {
        self._text = text
        self.highlightr.setTheme(to: "xcode") // Change theme as needed
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        
        // Configure text view
        textView.isEditable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 5, height: 5)
        
        // Apply Syntax Highlighting
        applyHighlighting(to: textView)
        
        // Wrap in scroll view
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if let textView = scrollView.documentView as? NSTextView {
            if textView.string != text {
                applyHighlighting(to: textView)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighlightrCodeEditor
        
        init(_ parent: HighlightrCodeEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            if let textView = notification.object as? NSTextView {
                parent.text = textView.string
            }
        }
    }
    
    private func applyHighlighting(to textView: NSTextView) {
        guard let highlightedCode = highlightr.highlight(text, as: "swift") else { return }
        textView.textStorage?.setAttributedString(highlightedCode)
    }
}



struct CodeEditorView: View {
    @State private var code: String = "Loading..."
    @ObservedObject var project: Project
    
    var body: some View {
        VStack {
            HStack {
                // Line Numbers
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .trailing) {
                        let lines = code.components(separatedBy: .newlines)
                        ForEach(0..<lines.count, id: \.self) { i in
                            Text("\(i + 1)")
                                .foregroundColor(.gray)
                                .font(.system(size: 14, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    .padding(.trailing, 5)
                }
                .frame(width: 40)
                
                // Syntax Highlighted Editor
                HighlightrCodeEditor(text: $code)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // Load File Button
            Button("Load File") {
                loadFile()
            }
        }
        .padding()
        .onAppear {
            loadFile()
        }
        
    }
    
    private func loadFile() {
        if let fileURL = project.selectedFile{
            DispatchQueue.global(qos: .background).async {
                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    DispatchQueue.main.async {
                        self.code = content
                    }
                }
            }
        }
    }
}

